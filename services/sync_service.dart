import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database.dart';

/// Offline-first sync. SQLite remains the working database. Supabase receives
/// rows only for the currently authenticated (anonymous) owner.
class SyncService {
  final AppDatabase db;
  SyncService(this.db);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;
  bool _isSyncing = false;

  static bool get isConfigured {
    try {
      return Supabase.instance.client.supabaseUrl.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void startAutoSync() {
    if (!isConfigured) return;
    _connectivitySubscription ??=
        Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        unawaited(_safeSync());
      }
    });
    _periodicTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_safeSync()),
    );
    unawaited(_safeSync());
  }

  Future<int> pendingCount() async {
    final rows = await (db.select(db.syncQueue)
          ..where((row) => row.status.equals('pending') | row.status.equals('failed')))
        .get();
    return rows.length;
  }

  Future<Map<String, int>> pendingByTable() async {
    final rows = await (db.select(db.syncQueue)
          ..where((row) => row.status.equals('pending') | row.status.equals('failed')))
        .get();
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row.entityType] = (counts[row.entityType] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _safeSync() async {
    try {
      await syncNow(retryFailed: false);
    } catch (_) {
      // Keep background sync failures from becoming uncaught async errors.
    }
  }

  /// A manual call retries items previously marked failed.
  Future<void> syncNow({bool retryFailed = true}) async {
    if (_isSyncing || !isConfigured) return;
    _isSyncing = true;
    try {
      final connection = await Connectivity().checkConnectivity();
      if (connection.contains(ConnectivityResult.none)) return;

      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      if (retryFailed) {
        await (db.update(db.syncQueue)
              ..where((row) => row.status.equals('failed')))
            .write(const SyncQueueCompanion(
          status: Value('pending'),
          retryCount: Value(0),
        ));
      }

      final pending = await (db.select(db.syncQueue)
            ..where((row) => row.status.equals('pending')))
          .get();
      // Upload parents before dependants even if several queue timestamps are
      // identical: customers/packages -> lines/history -> cycles -> payments
      // -> allocations. This avoids foreign-key races in the remote database.
      pending.sort((a, b) {
        final rank = _syncRank(a.entityType).compareTo(_syncRank(b.entityType));
        if (rank != 0) return rank;
        final created = a.createdAt.compareTo(b.createdAt);
        return created != 0 ? created : a.id.compareTo(b.id);
      });

      for (final item in pending) {
        try {
          final table = _tableFor(item.entityType);
          if (table == null) {
            await _markDone(item.id);
            continue;
          }
          final payload = await _buildPayload(item);
          if (payload == null) {
            // A missing local row is treated as already removed. Deletion sync
            // is not exposed by this app; this branch avoids a permanent queue.
            await _markDone(item.id);
            continue;
          }
          payload['owner_id'] = user.id;
          await client.from(table).upsert(payload, onConflict: 'id');
          await _markDone(item.id);
        } catch (_) {
          final nextRetry = item.retryCount + 1;
          await (db.update(db.syncQueue)
                ..where((row) => row.id.equals(item.id)))
              .write(SyncQueueCompanion(
            retryCount: Value(nextRetry),
            status: Value(nextRetry >= 5 ? 'failed' : 'pending'),
          ));
          if (nextRetry < 5) {
            final delayMs = min(1000 * pow(2, nextRetry).toInt(), 8000).toInt();
            await Future.delayed(Duration(milliseconds: delayMs));
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _markDone(String id) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      const SyncQueueCompanion(status: Value('done')),
    );
  }

  int _syncRank(String type) => switch (type) {
        'customer' || 'package' => 0,
        'package_price_history' || 'line' => 1,
        'billing_cycle' => 2,
        'payment' => 3,
        'payment_allocation' => 4,
        'expense' => 5,
        'audit' => 6,
        _ => 7,
      };

  String? _tableFor(String type) {
    switch (type) {
      case 'customer':
        return 'customers';
      case 'package':
        return 'packages';
      case 'package_price_history':
        return 'package_price_history';
      case 'line':
        return 'lines';
      case 'billing_cycle':
        return 'billing_cycles';
      case 'payment':
        return 'payments';
      case 'payment_allocation':
        return 'payment_allocations';
      case 'expense':
        return 'expenses';
      case 'audit':
        return 'audit_logs';
      default:
        return null;
    }
  }

  /// Always read the latest full row from SQLite. Never trust abbreviated queue
  /// payloads, which could otherwise overwrite remote columns with omissions.
  Future<Map<String, dynamic>?> _buildPayload(SyncQueueData item) async {
    switch (item.entityType) {
      case 'customer':
        final row = await (db.select(db.customers)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'name': row.name,
          'phone': row.phone,
          'whatsapp': row.whatsapp,
          'address': row.address,
          'notes': row.notes,
          'registered_at': row.registeredAt?.toIso8601String(),
          'is_archived': row.isArchived,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'deleted_at': row.deletedAt?.toIso8601String(),
        };
      case 'package':
        final row = await (db.select(db.packages)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'name': row.name,
          'price_piasters': row.pricePiasters,
          'description': row.description,
          'is_archived': row.isArchived,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'deleted_at': row.deletedAt?.toIso8601String(),
        };
      case 'package_price_history':
        final row = await (db.select(db.packagePriceHistory)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'package_id': row.packageId,
          'old_price_piasters': row.oldPricePiasters,
          'new_price_piasters': row.newPricePiasters,
          'effective_year': row.effectiveYear,
          'effective_month': row.effectiveMonth,
          'created_at': row.createdAt.toIso8601String(),
        };
      case 'line':
        final row = await (db.select(db.lines)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'customer_id': row.customerId,
          'package_id': row.packageId,
          'number': row.number,
          'carrier': row.carrier,
          'line_type': row.lineType,
          'owner_name': row.ownerName,
          'start_year': row.startYear,
          'start_month': row.startMonth,
          'status': row.status,
          'notes': row.notes,
          'credit_piasters': row.creditPiasters,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'deleted_at': row.deletedAt?.toIso8601String(),
          'stopped_at': row.stoppedAt?.toIso8601String(),
        };
      case 'billing_cycle':
        final row = await (db.select(db.billingCycles)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'line_id': row.lineId,
          'year': row.year,
          'month': row.month,
          'price_piasters': row.pricePiasters,
          'package_name_snapshot': row.packageNameSnapshot,
          'paid_piasters': row.paidPiasters,
          'status': row.status,
        };
      case 'payment':
        final row = await (db.select(db.payments)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'line_id': row.lineId,
          'customer_id': row.customerId,
          'amount_piasters': row.amountPiasters,
          'paid_at': row.paidAt.toIso8601String(),
          'method': row.method,
          'reference': row.reference,
          'idempotency_key': row.idempotencyKey,
          'notes': row.notes,
          'collector_name': row.collectorName,
          'receipt_number': row.receiptNumber,
          'is_voided': row.isVoided,
          'created_at': row.createdAt.toIso8601String(),
        };
      case 'payment_allocation':
        final row = await (db.select(db.paymentAllocations)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'payment_id': row.paymentId,
          'billing_cycle_id': row.billingCycleId,
          'amount_piasters': row.amountPiasters,
        };
      case 'expense':
        final row = await (db.select(db.expenses)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'title': row.title,
          'amount_piasters': row.amountPiasters,
          'spent_at': row.spentAt.toIso8601String(),
          'category': row.category,
          'notes': row.notes,
          'created_at': row.createdAt.toIso8601String(),
        };
      case 'audit':
        final row = await (db.select(db.auditLogs)
              ..where((r) => r.id.equals(item.entityId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'id': row.id,
          'entity_type': row.entityType,
          'entity_id': row.entityId,
          'action': row.action,
          'old_value': row.oldValue,
          'new_value': row.newValue,
          'created_at': row.createdAt.toIso8601String(),
        };
      default:
        return null;
    }
  }
}
