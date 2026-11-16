import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../lines/line_detail_screen.dart';
import '../payments/payment_form.dart';

class OverdueScreen extends StatelessWidget {
  const OverdueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final currentMonth = YearMonth.nowCairo();
    return Scaffold(
      appBar: AppBar(title: const Text('المتأخرات')),
      body: FutureBuilder<List<BillingCycle>>(
        future: db.select(db.billingCycles).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل المتأخرات'));
          }
          final grouped = <String, List<BillingCycle>>{};
          for (final cycle in snapshot.data ?? const <BillingCycle>[]) {
            final month = YearMonth(cycle.year, cycle.month);
            final remaining =
                (cycle.pricePiasters - cycle.paidPiasters).clamp(0, 1 << 62).toInt();
            if (month.compareTo(currentMonth) <= 0 && remaining > 0) {
              grouped.putIfAbsent(cycle.lineId, () => []).add(cycle);
            }
          }
          if (grouped.isEmpty) {
            return const Center(child: Text('لا توجد متأخرات — ممتاز!'));
          }
          final lineIds = grouped.keys.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lineIds.length,
            itemBuilder: (context, index) {
              final lineId = lineIds[index];
              final cycles = grouped[lineId]!;
              final total = cycles.fold<int>(
                0,
                (sum, cycle) => sum +
                    (cycle.pricePiasters - cycle.paidPiasters)
                        .clamp(0, 1 << 62).toInt(),
              );
              cycles.sort((a, b) =>
                  (a.year * 100 + a.month).compareTo(b.year * 100 + b.month));
              final oldest = cycles.first;
              return FutureBuilder<Line?>(
                future: (db.select(db.lines)..where((line) => line.id.equals(lineId)))
                    .getSingleOrNull(),
                builder: (context, lineSnapshot) {
                  final line = lineSnapshot.data;
                  if (line == null) return const SizedBox.shrink();
                  return FutureBuilder<Customer?>(
                    future: (db.select(db.customers)
                          ..where((customer) =>
                              customer.id.equals(line.customerId)))
                        .getSingleOrNull(),
                    builder: (context, customerSnapshot) {
                      final customer = customerSnapshot.data;
                      return Card(
                        child: ListTile(
                          title: Text('${customer?.name ?? 'عميل'} — ${line.number}'),
                          subtitle: Text(
                            '${cycles.length} شهر غير مسدد — أقدم شهر ${YearMonth(oldest.year, oldest.month).labelAr}\n'
                            'المتبقي: ${Money.format(total)}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'تسجيل دفعة',
                            icon: const Icon(Icons.payments),
                            onPressed: customer == null
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PaymentFormScreen(
                                          preselectedCustomer: customer,
                                          preselectedLine: line,
                                        ),
                                      ),
                                    ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LineDetailScreen(line: line),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
