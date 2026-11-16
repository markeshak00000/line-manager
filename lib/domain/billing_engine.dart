import '../core/year_month.dart';

/// Pure billing logic. All monetary values are integer piasters.
class BillingCycleData {
  final YearMonth ym;
  final int pricePiasters;
  final String packageName;
  final int paidPiasters;

  const BillingCycleData({
    required this.ym,
    required this.pricePiasters,
    required this.packageName,
    this.paidPiasters = 0,
  });

  int get remaining => (pricePiasters - paidPiasters).clamp(0, 1 << 62).toInt();

  String get status => paidPiasters <= 0
      ? 'unpaid'
      : (paidPiasters >= pricePiasters ? 'paid' : 'partial');

  bool get isPrepaid => ym.isFuture && status == 'paid';

  bool get isOverdue {
    final now = YearMonth.nowCairo();
    return ym.compareTo(now) <= 0 && remaining > 0;
  }
}

class AllocationResult {
  final Map<String, int> allocations;
  final int overpaymentPiasters;
  final int totalAllocated;

  const AllocationResult({
    required this.allocations,
    required this.overpaymentPiasters,
    required this.totalAllocated,
  });
}

class BillingEngine {
  static List<YearMonth> monthsBetween(
    YearMonth start,
    YearMonth end, {
    YearMonth? stoppedAt,
  }) {
    final result = <YearMonth>[];
    var current = start;
    while (current.compareTo(end) <= 0) {
      if (stoppedAt != null && current.compareTo(stoppedAt) > 0) break;
      result.add(current);
      current = current.next();
    }
    return result;
  }

  /// Allocate oldest to newest. Any amount that cannot be assigned to the
  /// selected cycles is returned explicitly as line credit.
  static AllocationResult allocate(
    List<BillingCycleData> cycles,
    int totalPiasters, {
    Map<String, int>? manual,
  }) {
    if (totalPiasters <= 0) {
      throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    }

    final byKey = <String, BillingCycleData>{};
    for (final cycle in cycles) {
      if (cycle.pricePiasters < 0 || cycle.paidPiasters < 0) {
        throw ArgumentError('بيانات الاشتراك غير صحيحة');
      }
      if (byKey.containsKey(cycle.ym.key)) {
        throw ArgumentError('تم اختيار الشهر أكثر من مرة');
      }
      byKey[cycle.ym.key] = cycle;
    }

    if (byKey.isEmpty) {
      throw ArgumentError('لا توجد شهور صالحة لتوزيع الدفعة عليها');
    }

    if (manual != null) {
      var sum = 0;
      for (final entry in manual.entries) {
        final cycle = byKey[entry.key];
        if (cycle == null) {
          throw ArgumentError('شهر غير موجود ضمن الشهور المختارة');
        }
        if (entry.value <= 0 || entry.value > cycle.remaining) {
          throw ArgumentError('قيمة التوزيع اليدوي غير صحيحة لشهر ${entry.key}');
        }
        sum += entry.value;
      }
      if (sum > totalPiasters) {
        throw ArgumentError('التوزيع اليدوي أكبر من المبلغ المدفوع');
      }
      if (sum == 0) {
        throw ArgumentError('يجب توزيع جزء من المبلغ على الأقل');
      }
      return AllocationResult(
        allocations: Map.unmodifiable(manual),
        overpaymentPiasters: totalPiasters - sum,
        totalAllocated: sum,
      );
    }

    final sorted = [...cycles]..sort((a, b) => a.ym.compareTo(b.ym));
    var left = totalPiasters;
    final allocations = <String, int>{};
    for (final cycle in sorted) {
      if (left <= 0) break;
      final amountNeeded = cycle.remaining;
      if (amountNeeded <= 0) continue;
      final amount = left < amountNeeded ? left : amountNeeded;
      allocations[cycle.ym.key] = amount;
      left -= amount;
    }

    return AllocationResult(
      allocations: Map.unmodifiable(allocations),
      overpaymentPiasters: left,
      totalAllocated: totalPiasters - left,
    );
  }

  static int totalArrears(List<BillingCycleData> cycles) {
    final now = YearMonth.nowCairo();
    return cycles
        .where((cycle) => cycle.ym.compareTo(now) <= 0)
        .fold(0, (sum, cycle) => sum + cycle.remaining);
  }

  static int totalPaid(List<BillingCycleData> cycles) =>
      cycles.fold(0, (sum, cycle) => sum + cycle.paidPiasters);

  static int remainingAfterPartial({
    required int price,
    required int oldPaid,
    required int newPayment,
  }) => (price - oldPaid - newPayment).clamp(0, 1 << 62).toInt();
}
