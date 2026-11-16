import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/money.dart';
import '../core/year_month.dart';
import '../domain/billing_engine.dart';
import 'database.dart';

class PaymentResult {
  final String id;
  final String receiptNumber;
  final int overpaymentPiasters;

  const PaymentResult({
    required this.id,
    required this.receiptNumber,
    required this.overpaymentPiasters,
  });
}

class SearchHit {
  final String type;
  final String title;
  final String subtitle;
  final String? customerId;
  final String? lineId;
  final String? paymentId;

  const SearchHit({
    required this.type,
    required this.title,
    required this.subtitle,
    this.customerId,
    this.lineId,
    this.paymentId,
  });
}

class Repos {
  final AppDatabase db;
  Repos(this.db);

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------
  Future<String> addCustomer({
    required String name,
    String? phone,
    String? whatsapp,
    String? address,
    String? notes,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('اسم العميل مطلوب');
    final id = const Uuid().v4();
    await db.transaction(() async {
      await db.into(db.customers).insert(CustomersCompanion.insert(
        id: id,
        name: cleanName,
        phone: Value(_emptyToNull(phone)),
        whatsapp: Value(_emptyToNull(whatsapp)),
        address: Value(_emptyToNull(address)),
        notes: Value(_emptyToNull(notes)),
        registeredAt: Value(DateTime.now()),
      ));
      await db.audit('customer', id, 'create', newV: cleanName);
      await db.enqueueSync('customer', id, 'upsert', '{}');
    });
    return id;
  }

  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? whatsapp,
    String? address,
    String? notes,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('اسم العميل مطلوب');
    await db.transaction(() async {
      final old = await (db.select(db.customers)..where((c) => c.id.equals(id)))
          .getSingle();
      await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
        CustomersCompanion(
          name: Value(cleanName),
          phone: Value(_emptyToNull(phone)),
          whatsapp: Value(_emptyToNull(whatsapp)),
          address: Value(_emptyToNull(address)),
          notes: Value(_emptyToNull(notes)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await db.audit('customer', id, 'update', oldV: old.name, newV: cleanName);
      await db.enqueueSync('customer', id, 'upsert', '{}');
    });
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final q = query.trim();
    final statement = db.select(db.customers)
      ..where((c) => c.deletedAt.isNull() & c.isArchived.equals(false));
    if (q.isNotEmpty) {
      final like = '%$q%';
      statement.where(
        (c) => c.name.like(like) | c.phone.like(like) | c.whatsapp.like(like),
      );
    }
    statement.orderBy([(c) => OrderingTerm(expression: c.name)]);
    return statement.get();
  }

  Future<List<Line>> linesForCustomer(String customerId) =>
      (db.select(db.lines)
            ..where((l) =>
                l.customerId.equals(customerId) & l.deletedAt.isNull())
            ..orderBy([(l) => OrderingTerm(expression: l.number)]))
          .get();

  // Search across customers, line numbers and receipt numbers.
  Future<List<SearchHit>> globalSearch(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final like = '%$term%';
    final result = <SearchHit>[];

    final customers = await (db.select(db.customers)
          ..where((c) =>
              c.deletedAt.isNull() &
              c.isArchived.equals(false) &
              (c.name.like(like) | c.phone.like(like) | c.whatsapp.like(like))))
        .get();
    for (final customer in customers) {
      result.add(SearchHit(
        type: 'customer',
        title: customer.name,
        subtitle: customer.phone ?? 'بدون رقم تواصل',
        customerId: customer.id,
      ));
    }

    final lines = await (db.select(db.lines)
          ..where((l) => l.deletedAt.isNull() & l.number.like(like)))
        .get();
    for (final line in lines) {
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(line.customerId)))
          .getSingleOrNull();
      result.add(SearchHit(
        type: 'line',
        title: line.number,
        subtitle: customer?.name ?? 'عميل غير معروف',
        customerId: line.customerId,
        lineId: line.id,
      ));
    }

    final payments = await (db.select(db.payments)
          ..where((p) => p.receiptNumber.like(like) & p.isVoided.equals(false)))
        .get();
    for (final payment in payments) {
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(payment.customerId)))
          .getSingleOrNull();
      result.add(SearchHit(
        type: 'payment',
        title: 'إيصال ${payment.receiptNumber}',
        subtitle: '${customer?.name ?? ''} — ${Money.format(payment.amountPiasters)}',
        customerId: payment.customerId,
        lineId: payment.lineId,
        paymentId: payment.id,
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Packages and price history
  // ---------------------------------------------------------------------------
  Future<String> addPackage(String name, int pricePiasters, String? description) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('اسم الباقة مطلوب');
    if (pricePiasters <= 0) throw ArgumentError('سعر الباقة يجب أن يكون أكبر من صفر');
    final id = const Uuid().v4();
    await db.transaction(() async {
      await db.into(db.packages).insert(PackagesCompanion.insert(
        id: id,
        name: cleanName,
        pricePiasters: pricePiasters,
        description: Value(_emptyToNull(description)),
      ));
      await db.audit('package', id, 'create', newV: '$cleanName:$pricePiasters');
      await db.enqueueSync('package', id, 'upsert', '{}');
    });
    return id;
  }

  Future<int> priceForMonth(String packageId, YearMonth month) async {
    final package = await (db.select(db.packages)
          ..where((p) => p.id.equals(packageId)))
        .getSingle();
    final history = await (db.select(db.packagePriceHistory)
          ..where((h) => h.packageId.equals(packageId)))
        .get();
    history.sort((a, b) {
      final aKey = a.effectiveYear * 100 + a.effectiveMonth;
      final bKey = b.effectiveYear * 100 + b.effectiveMonth;
      if (aKey != bKey) return aKey.compareTo(bKey);
      return a.createdAt.compareTo(b.createdAt);
    });

    var price = package.pricePiasters;
    if (history.isEmpty) return price;

    final monthKey = month.year * 100 + month.month;
    final first = history.first;
    if (monthKey < first.effectiveYear * 100 + first.effectiveMonth) {
      return first.oldPricePiasters;
    }
    for (final item in history) {
      final effectiveKey = item.effectiveYear * 100 + item.effectiveMonth;
      if (monthKey >= effectiveKey) price = item.newPricePiasters;
    }
    return price;
  }

  Future<void> archivePackage(String packageId) async {
    await db.transaction(() async {
      await (db.update(db.packages)..where((p) => p.id.equals(packageId))).write(
        PackagesCompanion(isArchived: const Value(true), deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())),
      );
      await db.audit('package', packageId, 'archive');
      await db.enqueueSync('package', packageId, 'upsert', '{}');
    });
  }

  Future<int> updatePackagePrice({
    required String packageId,
    required int newPrice,
    required YearMonth effective,
  }) async {
    if (newPrice <= 0) {
      throw ArgumentError('سعر الباقة يجب أن يكون أكبر من صفر');
    }

    return db.transaction(() async {
      await (db.select(db.packages)
            ..where((p) => p.id.equals(packageId)))
          .getSingle();
      final oldEffectivePrice = await priceForMonth(packageId, effective);
      if (newPrice == oldEffectivePrice) return 0;

      final historyId = const Uuid().v4();
      await db.into(db.packagePriceHistory).insert(
            PackagePriceHistoryCompanion.insert(
              id: historyId,
              packageId: packageId,
              oldPricePiasters: oldEffectivePrice,
              newPricePiasters: newPrice,
              effectiveYear: effective.year,
              effectiveMonth: effective.month,
            ),
          );
      await db.enqueueSync('package_price_history', historyId, 'upsert', '{}');

      // The package row stores the latest configured price; historical prices
      // remain resolved from package_price_history for each billing month.
      final allHistory = await (db.select(db.packagePriceHistory)
            ..where((h) => h.packageId.equals(packageId)))
          .get();
      allHistory.sort((a, b) {
        final aKey = a.effectiveYear * 100 + a.effectiveMonth;
        final bKey = b.effectiveYear * 100 + b.effectiveMonth;
        if (aKey != bKey) return aKey.compareTo(bKey);
        return a.createdAt.compareTo(b.createdAt);
      });
      final latestConfiguredPrice = allHistory.isEmpty
          ? newPrice
          : allHistory.last.newPricePiasters;
      await (db.update(db.packages)..where((p) => p.id.equals(packageId))).write(
        PackagesCompanion(
          pricePiasters: Value(latestConfiguredPrice),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await db.enqueueSync('package', packageId, 'upsert', '{}');

      final lines = await (db.select(db.lines)
            ..where((l) =>
                l.packageId.equals(packageId) &
                l.deletedAt.isNull() &
                (l.status.equals('active') | l.status.equals('paused'))))
          .get();
      var affected = 0;

      for (final line in lines) {
        final cycles = await (db.select(db.billingCycles)
              ..where((c) => c.lineId.equals(line.id)))
            .get();
        var addedCredit = 0;

        for (final cycle in cycles) {
          final month = YearMonth(cycle.year, cycle.month);
          if (month.compareTo(effective) < 0 ||
              cycle.paidPiasters >= cycle.pricePiasters) {
            continue;
          }

          final correctPrice = await priceForMonth(packageId, month);
          if (correctPrice == cycle.pricePiasters) continue;

          if (cycle.paidPiasters > correctPrice) {
            addedCredit += cycle.paidPiasters - correctPrice;
          }
          final newStatus = cycle.paidPiasters >= correctPrice
              ? 'paid'
              : (cycle.paidPiasters > 0 ? 'partial' : 'unpaid');
          await (db.update(db.billingCycles)
                ..where((c) => c.id.equals(cycle.id)))
              .write(BillingCyclesCompanion(
            pricePiasters: Value(correctPrice),
            status: Value(newStatus),
          ));
          await db.enqueueSync('billing_cycle', cycle.id, 'upsert', '{}');
          affected++;
        }

        if (addedCredit > 0) {
          final newCredit = line.creditPiasters + addedCredit;
          await (db.update(db.lines)..where((l) => l.id.equals(line.id))).write(
            LinesCompanion(creditPiasters: Value(newCredit)),
          );
          await db.enqueueSync('line', line.id, 'upsert', '{}');
          await db.audit(
            'line',
            line.id,
            'price_decrease_credit',
            oldV: '${line.creditPiasters}',
            newV: '$newCredit',
          );
        }
      }

      await db.audit(
        'package',
        packageId,
        'price_change',
        oldV: '$oldEffectivePrice',
        newV: '$newPrice @ ${effective.key}',
      );
      return affected;
    });
  }

  // ---------------------------------------------------------------------------
  // Lines and monthly billing cycles
  // ---------------------------------------------------------------------------
  Future<String> addLine({
    required String customerId,
    required String packageId,
    required String number,
    String carrier = 'Orange',
    String type = 'calls',
    String? owner,
    String? notes,
    YearMonth? start,
  }) async {
    final cleanNumber = number.replaceAll(RegExp(r'\s+'), '');
    if (cleanNumber.isEmpty) throw ArgumentError('رقم الخط مطلوب');
    final customer = await (db.select(db.customers)
          ..where((c) => c.id.equals(customerId) & c.deletedAt.isNull()))
        .getSingleOrNull();
    if (customer == null) throw ArgumentError('العميل غير موجود');
    final package = await (db.select(db.packages)
          ..where((p) => p.id.equals(packageId) & p.isArchived.equals(false)))
        .getSingleOrNull();
    if (package == null) throw ArgumentError('الباقة غير موجودة أو مؤرشفة');

    final id = const Uuid().v4();
    await db.transaction(() async {
      await db.into(db.lines).insert(LinesCompanion.insert(
        id: id,
        customerId: customerId,
        packageId: packageId,
        number: cleanNumber,
        carrier: Value(carrier),
        lineType: Value(type),
        ownerName: Value(_emptyToNull(owner)),
        notes: Value(_emptyToNull(notes)),
        startYear: Value((start ?? YearMonth.nowCairo()).year),
        startMonth: Value((start ?? YearMonth.nowCairo()).month),
      ));
      await db.enqueueSync('line', id, 'upsert', '{}');
      final firstMonth = start ?? YearMonth.nowCairo();
      final now = YearMonth.nowCairo();
      for (final month in BillingEngine.monthsBetween(firstMonth, now)) {
        final price = await priceForMonth(packageId, month);
        await _insertCycle(
          lineId: id,
          month: month,
          price: price,
          packageName: package.name,
        );
      }
      await db.audit('line', id, 'create', newV: cleanNumber);
    });
    return id;
  }

  Future<void> updateLine({
    required String id,
    String? number,
    String? packageId,
    String? lineType,
    String? status,
    String? notes,
    String? ownerName,
    bool clearNotes = false,
    bool clearOwnerName = false,
  }) async {
    await db.transaction(() async {
      final old = await (db.select(db.lines)..where((l) => l.id.equals(id)))
          .getSingle();
      if (packageId != null && packageId != old.packageId) {
        final package = await (db.select(db.packages)
              ..where((p) => p.id.equals(packageId) & p.isArchived.equals(false)))
            .getSingleOrNull();
        if (package == null) throw ArgumentError('الباقة الجديدة غير موجودة أو مؤرشفة');
      }
      final nextStatus = status ?? old.status;
      final reactivating = old.status != 'active' && nextStatus == 'active';
      final packageChanged = packageId != null && packageId != old.packageId;
      final currentMonth = YearMonth.nowCairo();
      await (db.update(db.lines)..where((l) => l.id.equals(id))).write(
        LinesCompanion(
          number: number != null ? Value(number.trim()) : const Value.absent(),
          packageId: packageId != null ? Value(packageId) : const Value.absent(),
          lineType: lineType != null ? Value(lineType) : const Value.absent(),
          status: status != null ? Value(status) : const Value.absent(),
          notes: clearNotes ? const Value(null) : (notes != null ? Value(_emptyToNull(notes)) : const Value.absent()),
          ownerName: clearOwnerName ? const Value(null) : (ownerName != null ? Value(_emptyToNull(ownerName)) : const Value.absent()),
          startYear: reactivating ? Value(currentMonth.year) : const Value.absent(),
          startMonth: reactivating ? Value(currentMonth.month) : const Value.absent(),
          stoppedAt: nextStatus == 'active'
              ? const Value(null)
              : (old.stoppedAt == null ? Value(DateTime.now()) : Value(old.stoppedAt)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (packageChanged) {
        final nextPackageId = packageId!;
        final nextPackage = await (db.select(db.packages)
              ..where((p) => p.id.equals(nextPackageId)))
            .getSingle();
        final cycles = await (db.select(db.billingCycles)
              ..where((c) => c.lineId.equals(id)))
            .get();
        var priceDifferenceCredit = 0;
        for (final cycle in cycles) {
          final month = YearMonth(cycle.year, cycle.month);
          if (month.compareTo(currentMonth) < 0 ||
              cycle.paidPiasters >= cycle.pricePiasters) {
            continue;
          }
          final nextPrice = await priceForMonth(nextPackageId, month);
          if (nextPrice == cycle.pricePiasters) continue;
          if (cycle.paidPiasters > nextPrice) {
            priceDifferenceCredit += cycle.paidPiasters - nextPrice;
          }
          await (db.update(db.billingCycles)
                ..where((c) => c.id.equals(cycle.id)))
              .write(BillingCyclesCompanion(
            pricePiasters: Value(nextPrice),
            packageNameSnapshot: Value(nextPackage.name),
            status: Value(cycle.paidPiasters >= nextPrice
                ? 'paid'
                : (cycle.paidPiasters > 0 ? 'partial' : 'unpaid')),
          ));
          await db.enqueueSync('billing_cycle', cycle.id, 'upsert', '{}');
        }
        if (priceDifferenceCredit > 0) {
          await (db.update(db.lines)..where((l) => l.id.equals(id))).write(
            LinesCompanion(
              creditPiasters: Value(old.creditPiasters + priceDifferenceCredit),
            ),
          );
          await db.audit(
            'line',
            id,
            'package_change_credit',
            oldV: '${old.creditPiasters}',
            newV: '${old.creditPiasters + priceDifferenceCredit}',
          );
        }
      }
      await db.audit(
        'line',
        id,
        'update',
        oldV: '${old.number}:${old.packageId}',
        newV: '${number?.trim() ?? old.number}:${packageId ?? old.packageId}',
      );
      await db.enqueueSync('line', id, 'upsert', '{}');
    });
  }

  Future<List<BillingCycle>> cyclesForLine(String lineId) =>
      (db.select(db.billingCycles)
            ..where((c) => c.lineId.equals(lineId))
            ..orderBy([
              (c) => OrderingTerm(expression: c.year),
              (c) => OrderingTerm(expression: c.month),
            ]))
          .get();

  Future<void> _insertCycle({
    required String lineId,
    required YearMonth month,
    required int price,
    required String packageName,
  }) async {
    final id = const Uuid().v4();
    await db.into(db.billingCycles).insert(BillingCyclesCompanion.insert(
      id: id,
      lineId: lineId,
      year: month.year,
      month: month.month,
      pricePiasters: price,
      packageNameSnapshot: packageName,
    ));
    await db.enqueueSync('billing_cycle', id, 'upsert', '{}');
  }

  Future<void> ensureCycle(
    String lineId,
    YearMonth month,
    int price,
    String packageName,
  ) async {
    final existing = await (db.select(db.billingCycles)
          ..where((c) =>
              c.lineId.equals(lineId) &
              c.year.equals(month.year) &
              c.month.equals(month.month)))
        .getSingleOrNull();
    if (existing == null) {
      await _insertCycle(
        lineId: lineId,
        month: month,
        price: price,
        packageName: packageName,
      );
    }
  }

  Future<int> ensureCyclesForAllActiveLines() async {
    final now = YearMonth.nowCairo();
    var created = 0;
    final lines = await (db.select(db.lines)
          ..where((l) =>
              l.status.equals('active') & l.deletedAt.isNull()))
        .get();
    for (final line in lines) {
      final package = await (db.select(db.packages)
            ..where((p) => p.id.equals(line.packageId)))
          .getSingleOrNull();
      if (package == null) continue;
      final start = line.startYear != null && line.startMonth != null
          ? YearMonth(line.startYear!, line.startMonth!)
          : YearMonth(line.createdAt.year, line.createdAt.month);
      final existingCycles = await cyclesForLine(line.id);
      var end = now;
      final existingKeys = <String>{};
      for (final cycle in existingCycles) {
        final cycleMonth = YearMonth(cycle.year, cycle.month);
        existingKeys.add(cycleMonth.key);
        if (cycleMonth.compareTo(end) > 0) end = cycleMonth;
      }

      // Fill monthly gaps through the furthest already-created prepaid month.
      // This makes a prepaid March cycle also create February if it was absent.
      for (final month in BillingEngine.monthsBetween(start, end)) {
        if (existingKeys.contains(month.key)) continue;
        final price = await priceForMonth(line.packageId, month);
        await _insertCycle(
          lineId: line.id,
          month: month,
          price: price,
          packageName: package.name,
        );
        existingKeys.add(month.key);
        created++;
      }
    }
    return created;
  }

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------
  Future<PaymentResult> recordPayment({
    required String lineId,
    required String customerId,
    required int amountPiasters,
    required List<YearMonth> months,
    DateTime? paidAt,
    String method = 'cash',
    String? reference,
    String? notes,
    String collector = 'ماما',
    String? idempotencyKey,
    Map<String, int>? manualAllocation,
  }) async {
    if (amountPiasters <= 0) throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    if (months.isEmpty) throw ArgumentError('اختر شهرًا واحدًا على الأقل');
    final uniqueMonths = <String>{};
    for (final month in months) {
      if (month.month < 1 || month.month > 12 || month.year < 2000 || month.year > 2200) {
        throw ArgumentError('أحد الشهور المختارة غير صالح');
      }
      if (!uniqueMonths.add(month.key)) throw ArgumentError('تم اختيار الشهر أكثر من مرة');
    }

    return db.transaction(() async {
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        final existing = await (db.select(db.payments)
              ..where((p) => p.idempotencyKey.equals(idempotencyKey)))
            .getSingleOrNull();
        if (existing != null) {
          return PaymentResult(
            id: existing.id,
            receiptNumber: existing.receiptNumber,
            overpaymentPiasters: 0,
          );
        }
      }

      final line = await (db.select(db.lines)..where((l) => l.id.equals(lineId)))
          .getSingle();
      if (line.customerId != customerId) {
        throw ArgumentError('العميل لا يطابق صاحب الخط');
      }
      if (line.deletedAt != null || line.status == 'cancelled') {
        throw ArgumentError('لا يمكن تسجيل دفعة لخط ملغي أو مؤرشف');
      }
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId) & c.deletedAt.isNull()))
          .getSingleOrNull();
      if (customer == null) throw ArgumentError('العميل غير موجود');
      final package = await (db.select(db.packages)
            ..where((p) => p.id.equals(line.packageId)))
          .getSingle();

      final sortedMonths = [...months]..sort((a, b) => a.compareTo(b));
      final lineStart = YearMonth(
        line.startYear ?? line.createdAt.year,
        line.startMonth ?? line.createdAt.month,
      );
      if (sortedMonths.first.compareTo(lineStart) < 0) {
        throw ArgumentError('لا يمكن تسجيل دفعة عن شهر يسبق بداية الخط');
      }

      // Create every monthly cycle through the furthest selected month. This
      // prevents gaps when a user prepays a distant future month (for example
      // March) while February has not yet been generated locally.
      final existingBeforePayment = await cyclesForLine(lineId);
      final existingKeys = existingBeforePayment
          .map((cycle) => '${cycle.year}-${cycle.month.toString().padLeft(2, '0')}')
          .toSet();
      for (final month in BillingEngine.monthsBetween(lineStart, sortedMonths.last)) {
        if (existingKeys.contains(month.key)) continue;
        final monthPrice = await priceForMonth(line.packageId, month);
        await _insertCycle(
          lineId: lineId,
          month: month,
          price: monthPrice,
          packageName: package.name,
        );
        existingKeys.add(month.key);
      }

      final allCycles = await cyclesForLine(lineId);
      final selectedCycles = allCycles
          .where((cycle) => months.any((m) =>
              m.year == cycle.year && m.month == cycle.month))
          .toList();
      if (selectedCycles.length != months.length) {
        throw StateError('تعذر تجهيز كل الشهور المختارة');
      }
      final cycleData = selectedCycles
          .map((cycle) => BillingCycleData(
                ym: YearMonth(cycle.year, cycle.month),
                pricePiasters: cycle.pricePiasters,
                packageName: cycle.packageNameSnapshot,
                paidPiasters: cycle.paidPiasters,
              ))
          .toList();
      final allocation = BillingEngine.allocate(
        cycleData,
        amountPiasters,
        manual: manualAllocation,
      );

      final paymentId = const Uuid().v4();
      final receiptNumber =
          'LM-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4().substring(0, 8)}';
      await db.into(db.payments).insert(PaymentsCompanion.insert(
        id: paymentId,
        lineId: lineId,
        customerId: customerId,
        amountPiasters: amountPiasters,
        paidAt: paidAt ?? DateTime.now(),
        method: Value(method),
        reference: Value(_emptyToNull(reference)),
        idempotencyKey: Value(_emptyToNull(idempotencyKey)),
        notes: Value(_emptyToNull(notes)),
        collectorName: Value(collector.trim().isEmpty ? 'ماما' : collector.trim()),
        receiptNumber: receiptNumber,
      ));
      await db.enqueueSync('payment', paymentId, 'upsert', '{}');

      for (final entry in allocation.allocations.entries) {
        final parts = entry.key.split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final cycle = selectedCycles.firstWhere(
          (item) => item.year == year && item.month == month,
        );
        final newPaid = cycle.paidPiasters + entry.value;
        await (db.update(db.billingCycles)
              ..where((c) => c.id.equals(cycle.id)))
            .write(BillingCyclesCompanion(
          paidPiasters: Value(newPaid),
          status: Value(newPaid >= cycle.pricePiasters
              ? 'paid'
              : (newPaid > 0 ? 'partial' : 'unpaid')),
        ));
        final allocationId = const Uuid().v4();
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                id: allocationId,
                paymentId: paymentId,
                billingCycleId: cycle.id,
                amountPiasters: entry.value,
              ),
            );
        await db.enqueueSync('billing_cycle', cycle.id, 'upsert', '{}');
        await db.enqueueSync('payment_allocation', allocationId, 'upsert', '{}');
      }

      if (allocation.overpaymentPiasters > 0) {
        final newCredit = line.creditPiasters + allocation.overpaymentPiasters;
        await (db.update(db.lines)..where((l) => l.id.equals(lineId))).write(
          LinesCompanion(creditPiasters: Value(newCredit)),
        );
        await db.audit(
          'line',
          lineId,
          'credit_added',
          oldV: '${line.creditPiasters}',
          newV: '$newCredit',
        );
        await db.enqueueSync('line', lineId, 'upsert', '{}');
      }

      await db.audit('payment', paymentId, 'create', newV: '$amountPiasters');
      return PaymentResult(
        id: paymentId,
        receiptNumber: receiptNumber,
        overpaymentPiasters: allocation.overpaymentPiasters,
      );
    });
  }

  Future<void> voidPayment(String paymentId) async {
    await db.transaction(() async {
      final payment = await (db.select(db.payments)
            ..where((p) => p.id.equals(paymentId)))
          .getSingle();
      if (payment.isVoided) return;

      final allocations = await (db.select(db.paymentAllocations)
            ..where((a) => a.paymentId.equals(paymentId)))
          .get();
      final allocatedTotal = allocations.fold<int>(
        0,
        (sum, allocation) => sum + allocation.amountPiasters,
      );
      final creditPart =
          (payment.amountPiasters - allocatedTotal).clamp(0, 1 << 62).toInt();

      for (final allocation in allocations) {
        final cycle = await (db.select(db.billingCycles)
              ..where((c) => c.id.equals(allocation.billingCycleId)))
            .getSingle();
        final newPaid =
            (cycle.paidPiasters - allocation.amountPiasters).clamp(0, 1 << 62).toInt();
        await (db.update(db.billingCycles)
              ..where((c) => c.id.equals(cycle.id)))
            .write(BillingCyclesCompanion(
          paidPiasters: Value(newPaid),
          status: Value(newPaid >= cycle.pricePiasters
              ? 'paid'
              : (newPaid > 0 ? 'partial' : 'unpaid')),
        ));
        // Keep the allocation as historical evidence. The payment is marked void.
        await db.enqueueSync('billing_cycle', cycle.id, 'upsert', '{}');
      }

      if (creditPart > 0) {
        final line = await (db.select(db.lines)
              ..where((l) => l.id.equals(payment.lineId)))
            .getSingle();
        final newCredit = (line.creditPiasters - creditPart).clamp(0, 1 << 62).toInt();
        await (db.update(db.lines)..where((l) => l.id.equals(payment.lineId)))
            .write(LinesCompanion(creditPiasters: Value(newCredit)));
        await db.enqueueSync('line', payment.lineId, 'upsert', '{}');
      }

      await (db.update(db.payments)..where((p) => p.id.equals(paymentId))).write(
        PaymentsCompanion(isVoided: const Value(true)),
      );
      await db.audit('payment', paymentId, 'void', oldV: '${payment.amountPiasters}');
      await db.enqueueSync('payment', paymentId, 'upsert', '{}');
    });
  }

  Future<List<Payment>> recentPayments({int limit = 20}) =>
      (db.select(db.payments)
            ..where((p) => p.isVoided.equals(false))
            ..orderBy([
              (p) => OrderingTerm(
                    expression: p.paidAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(limit))
          .get();

  Future<int> totalCollectedForMonth(YearMonth month) async {
    final payments = await (db.select(db.payments)
          ..where((p) => p.isVoided.equals(false)))
        .get();
    return payments
        .where((p) => p.paidAt.year == month.year && p.paidAt.month == month.month)
        .fold(0, (sum, payment) => sum + payment.amountPiasters);
  }

  Future<int> arrearsForLine(String lineId) async {
    final cycles = await cyclesForLine(lineId);
    final now = YearMonth.nowCairo();
    return cycles
        .where((cycle) => YearMonth(cycle.year, cycle.month).compareTo(now) <= 0)
        .fold<int>(
          0,
          (sum, cycle) =>
              sum + (cycle.pricePiasters - cycle.paidPiasters).clamp(0, 1 << 62).toInt(),
        );
  }

  // ---------------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------------
  Future<String> addExpense({
    required String title,
    required int amountPiasters,
    DateTime? spentAt,
    String? category,
    String? notes,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw ArgumentError('اسم المصروف مطلوب');
    if (amountPiasters <= 0) throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    final id = const Uuid().v4();
    await db.transaction(() async {
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: id,
        title: cleanTitle,
        amountPiasters: amountPiasters,
        spentAt: spentAt ?? DateTime.now(),
        category: Value(_emptyToNull(category)),
        notes: Value(_emptyToNull(notes)),
      ));
      await db.audit('expense', id, 'create', newV: '$amountPiasters');
      await db.enqueueSync('expense', id, 'upsert', '{}');
    });
    return id;
  }

  String? _emptyToNull(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
