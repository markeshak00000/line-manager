import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';

/// Full local backup/restore for all business data tables.
class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  Future<File> exportJson() async {
    final data = <String, dynamic>{
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'customers': (await db.select(db.customers).get())
          .map((row) => {
                'id': row.id,
                'name': row.name,
                'phone': row.phone,
                'whatsapp': row.whatsapp,
                'address': row.address,
                'notes': row.notes,
                'registeredAt': _iso(row.registeredAt),
                'isArchived': row.isArchived,
                'createdAt': row.createdAt.toIso8601String(),
                'updatedAt': row.updatedAt.toIso8601String(),
                'deletedAt': _iso(row.deletedAt),
              })
          .toList(),
      'packages': (await db.select(db.packages).get())
          .map((row) => {
                'id': row.id,
                'name': row.name,
                'pricePiasters': row.pricePiasters,
                'description': row.description,
                'isArchived': row.isArchived,
                'createdAt': row.createdAt.toIso8601String(),
                'updatedAt': row.updatedAt.toIso8601String(),
                'deletedAt': _iso(row.deletedAt),
              })
          .toList(),
      'package_price_history': (await db.select(db.packagePriceHistory).get())
          .map((row) => {
                'id': row.id,
                'packageId': row.packageId,
                'oldPricePiasters': row.oldPricePiasters,
                'newPricePiasters': row.newPricePiasters,
                'effectiveYear': row.effectiveYear,
                'effectiveMonth': row.effectiveMonth,
                'createdAt': row.createdAt.toIso8601String(),
              })
          .toList(),
      'lines': (await db.select(db.lines).get())
          .map((row) => {
                'id': row.id,
                'customerId': row.customerId,
                'packageId': row.packageId,
                'number': row.number,
                'carrier': row.carrier,
                'lineType': row.lineType,
                'ownerName': row.ownerName,
                'startYear': row.startYear,
                'startMonth': row.startMonth,
                'status': row.status,
                'notes': row.notes,
                'creditPiasters': row.creditPiasters,
                'createdAt': row.createdAt.toIso8601String(),
                'updatedAt': row.updatedAt.toIso8601String(),
                'deletedAt': _iso(row.deletedAt),
                'stoppedAt': _iso(row.stoppedAt),
              })
          .toList(),
      'billing_cycles': (await db.select(db.billingCycles).get())
          .map((row) => {
                'id': row.id,
                'lineId': row.lineId,
                'year': row.year,
                'month': row.month,
                'pricePiasters': row.pricePiasters,
                'packageNameSnapshot': row.packageNameSnapshot,
                'paidPiasters': row.paidPiasters,
                'status': row.status,
              })
          .toList(),
      'payments': (await db.select(db.payments).get())
          .map((row) => {
                'id': row.id,
                'lineId': row.lineId,
                'customerId': row.customerId,
                'amountPiasters': row.amountPiasters,
                'paidAt': row.paidAt.toIso8601String(),
                'method': row.method,
                'reference': row.reference,
                'idempotencyKey': row.idempotencyKey,
                'notes': row.notes,
                'collectorName': row.collectorName,
                'receiptNumber': row.receiptNumber,
                'isVoided': row.isVoided,
                'createdAt': row.createdAt.toIso8601String(),
              })
          .toList(),
      'payment_allocations': (await db.select(db.paymentAllocations).get())
          .map((row) => {
                'id': row.id,
                'paymentId': row.paymentId,
                'billingCycleId': row.billingCycleId,
                'amountPiasters': row.amountPiasters,
              })
          .toList(),
      'expenses': (await db.select(db.expenses).get())
          .map((row) => {
                'id': row.id,
                'title': row.title,
                'amountPiasters': row.amountPiasters,
                'spentAt': row.spentAt.toIso8601String(),
                'category': row.category,
                'notes': row.notes,
                'createdAt': row.createdAt.toIso8601String(),
              })
          .toList(),
      'notifications': (await db.select(db.notifications).get())
          .map((row) => {
                'id': row.id,
                'lineId': row.lineId,
                'title': row.title,
                'body': row.body,
                'scheduledAt': row.scheduledAt.toIso8601String(),
                'isSent': row.isSent,
              })
          .toList(),
      'audit_logs': (await db.select(db.auditLogs).get())
          .map((row) => {
                'id': row.id,
                'entityType': row.entityType,
                'entityId': row.entityId,
                'action': row.action,
                'oldValue': row.oldValue,
                'newValue': row.newValue,
                'createdAt': row.createdAt.toIso8601String(),
              })
          .toList(),
      'app_settings': (await db.select(db.appSettings).get())
          .map((row) => {'key': row.key, 'value': row.value})
          .toList(),
    };

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/line_manager_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    return file;
  }

  Future<void> shareBackup() async {
    final file = await exportJson();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      text: 'نسخة احتياطية — إدارة خطوط العملاء',
    );
  }

  Future<int> importJsonFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    if (selection == null || selection.files.isEmpty) return 0;
    final path = selection.files.single.path;
    if (path == null) throw StateError('تعذر قراءة مسار ملف النسخة الاحتياطية');

    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح');
    }
    final version = decoded['version'];
    if (version is! int || version < 1 || version > 2) {
      throw const FormatException('إصدار النسخة الاحتياطية غير مدعوم');
    }
    for (final key in ['customers', 'packages', 'lines', 'payments']) {
      if (decoded[key] is! List) {
        throw FormatException('الملف لا يحتوي على قائمة $key المطلوبة');
      }
    }

    return db.transaction(() async {
      var count = 0;
      // Delete child records before parent records to respect foreign keys.
      await db.delete(db.syncQueue).go();
      await db.delete(db.notifications).go();
      await db.delete(db.appSettings).go();
      await db.delete(db.paymentAllocations).go();
      await db.delete(db.payments).go();
      await db.delete(db.billingCycles).go();
      await db.delete(db.packagePriceHistory).go();
      await db.delete(db.expenses).go();
      await db.delete(db.auditLogs).go();
      await db.delete(db.lines).go();
      await db.delete(db.customers).go();
      await db.delete(db.packages).go();

      for (final row in _maps(decoded['customers'])) {
        await db.into(db.customers).insert(CustomersCompanion.insert(
          id: row['id'],
          name: row['name'],
          phone: Value(row['phone']),
          whatsapp: Value(row['whatsapp']),
          address: Value(row['address']),
          notes: Value(row['notes']),
          registeredAt: Value(_date(row['registeredAt'])),
          isArchived: Value(row['isArchived'] ?? false),
          createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
          updatedAt: Value(_date(row['updatedAt']) ?? DateTime.now()),
          deletedAt: Value(_date(row['deletedAt'])),
        ));
        count++;
      }

      for (final row in _maps(decoded['packages'])) {
        await db.into(db.packages).insert(PackagesCompanion.insert(
          id: row['id'],
          name: row['name'],
          pricePiasters: row['pricePiasters'],
          description: Value(row['description']),
          isArchived: Value(row['isArchived'] ?? false),
          createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
          updatedAt: Value(_date(row['updatedAt']) ?? DateTime.now()),
          deletedAt: Value(_date(row['deletedAt'])),
        ));
        count++;
      }

      for (final row in _maps(decoded['package_price_history'])) {
        await db.into(db.packagePriceHistory).insert(
              PackagePriceHistoryCompanion.insert(
                id: row['id'],
                packageId: row['packageId'],
                oldPricePiasters: row['oldPricePiasters'] ?? row['old'],
                newPricePiasters: row['newPricePiasters'] ?? row['new'],
                effectiveYear: row['effectiveYear'] ?? row['y'],
                effectiveMonth: row['effectiveMonth'] ?? row['m'],
                createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
              ),
            );
        count++;
      }

      for (final row in _maps(decoded['lines'])) {
        await db.into(db.lines).insert(LinesCompanion.insert(
          id: row['id'],
          customerId: row['customerId'],
          packageId: row['packageId'],
          number: row['number'],
          carrier: Value(row['carrier'] ?? 'Orange'),
          lineType: Value(row['lineType'] ?? 'calls'),
          ownerName: Value(row['ownerName']),
          startYear: Value(row['startYear']),
          startMonth: Value(row['startMonth']),
          status: Value(row['status'] ?? 'active'),
          notes: Value(row['notes']),
          creditPiasters: Value(row['creditPiasters'] ?? 0),
          createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
          updatedAt: Value(_date(row['updatedAt']) ?? DateTime.now()),
          deletedAt: Value(_date(row['deletedAt'])),
          stoppedAt: Value(_date(row['stoppedAt'])),
        ));
        count++;
      }

      for (final row in _maps(decoded['billing_cycles'])) {
        await db.into(db.billingCycles).insert(BillingCyclesCompanion.insert(
          id: row['id'],
          lineId: row['lineId'],
          year: row['year'],
          month: row['month'],
          pricePiasters: row['pricePiasters'],
          packageNameSnapshot: row['packageNameSnapshot'],
          paidPiasters: Value(row['paidPiasters'] ?? 0),
          status: Value(row['status'] ?? 'unpaid'),
        ));
        count++;
      }

      for (final row in _maps(decoded['payments'])) {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
          id: row['id'],
          lineId: row['lineId'],
          customerId: row['customerId'],
          amountPiasters: row['amountPiasters'],
          paidAt: DateTime.parse(row['paidAt']),
          method: Value(row['method'] ?? 'cash'),
          reference: Value(row['reference']),
          idempotencyKey: Value(row['idempotencyKey']),
          notes: Value(row['notes']),
          collectorName: Value(row['collectorName'] ?? 'ماما'),
          receiptNumber: row['receiptNumber'],
          isVoided: Value(row['isVoided'] ?? false),
          createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
        ));
        count++;
      }

      for (final row in _maps(decoded['payment_allocations'])) {
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                id: row['id'],
                paymentId: row['paymentId'],
                billingCycleId: row['billingCycleId'],
                amountPiasters: row['amountPiasters'],
              ),
            );
        count++;
      }

      for (final row in _maps(decoded['expenses'])) {
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: row['id'],
          title: row['title'],
          amountPiasters: row['amountPiasters'],
          spentAt: DateTime.parse(row['spentAt']),
          category: Value(row['category']),
          notes: Value(row['notes']),
          createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
        ));
        count++;
      }

      for (final row in _maps(decoded['notifications'])) {
        await db.into(db.notifications).insert(NotificationsCompanion.insert(
          id: row['id'],
          lineId: Value(row['lineId']),
          title: row['title'],
          body: row['body'],
          scheduledAt: DateTime.parse(row['scheduledAt']),
          isSent: Value(row['isSent'] ?? false),
        ));
        count++;
      }

      for (final row in _maps(decoded['audit_logs'])) {
        await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: row['id'],
          entityType: row['entityType'],
          entityId: Value(row['entityId']),
          action: row['action'],
          oldValue: Value(row['oldValue']),
          newValue: Value(row['newValue']),
          createdAt: Value(_date(row['createdAt']) ?? DateTime.now()),
        ));
        count++;
      }

      for (final row in _maps(decoded['app_settings'])) {
        await db.into(db.appSettings).insert(AppSettingsCompanion.insert(
          key: row['key'],
          value: row['value'],
        ));
        count++;
      }

      // Rebuild a fresh sync queue for restored business records.
      for (final row in _maps(decoded['customers'])) {
        await db.enqueueSync('customer', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['packages'])) {
        await db.enqueueSync('package', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['package_price_history'])) {
        await db.enqueueSync('package_price_history', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['lines'])) {
        await db.enqueueSync('line', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['billing_cycles'])) {
        await db.enqueueSync('billing_cycle', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['payments'])) {
        await db.enqueueSync('payment', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['payment_allocations'])) {
        await db.enqueueSync('payment_allocation', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['expenses'])) {
        await db.enqueueSync('expense', row['id'], 'upsert', '{}');
      }
      for (final row in _maps(decoded['audit_logs'])) {
        await db.enqueueSync('audit', row['id'], 'upsert', '{}');
      }
      return count;
    });
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value == null) return const [];
    if (value is! List) throw const FormatException('قائمة بيانات غير صالحة');
    return value.map((item) {
      if (item is! Map) throw const FormatException('سجل غير صالح في النسخة الاحتياطية');
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  DateTime? _date(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.parse(value.toString());
  }

  String? _iso(DateTime? value) => value?.toIso8601String();
}
