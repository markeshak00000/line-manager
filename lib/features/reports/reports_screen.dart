import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../services/export_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _filter = 'month';
  final TextEditingController _expenseTitle = TextEditingController();
  final TextEditingController _expenseAmount = TextEditingController();
  DateTimeRange? _customRange;

  @override
  void dispose() {
    _expenseTitle.dispose();
    _expenseAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final repos = context.read<Repos>();
    final now = DateTime.now();
    late DateTime from;
    late DateTime to;

    if (_filter == 'today') {
      from = DateTime(now.year, now.month, now.day);
      to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (_filter == 'prev') {
      from = DateTime(now.year, now.month - 1, 1);
      to = DateTime(now.year, now.month, 1).subtract(const Duration(microseconds: 1));
    } else if (_filter == 'year') {
      from = DateTime(now.year, 1, 1);
      to = now;
    } else if (_filter == 'custom' && _customRange != null) {
      from = _customRange!.start;
      to = DateTime(
        _customRange!.end.year,
        _customRange!.end.month,
        _customRange!.end.day,
        23,
        59,
        59,
        999,
      );
    } else {
      from = DateTime(now.year, now.month, 1);
      to = now;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ['today', 'اليوم'],
                ['month', 'هذا الشهر'],
                ['prev', 'الشهر السابق'],
                ['year', 'السنة الحالية'],
                ['custom', 'فترة مخصصة'],
              ].map((item) {
                return ChoiceChip(
                  label: Text(item[1]),
                  selected: _filter == item[0],
                  onSelected: (_) async {
                    if (item[0] == 'custom') {
                      final selected = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (selected == null || !mounted) return;
                      setState(() {
                        _customRange = selected;
                        _filter = 'custom';
                      });
                    } else {
                      setState(() => _filter = item[0]);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<dynamic>>(
              future: Future.wait([
                (db.select(db.payments)).get(),
                (db.select(db.expenses)).get(),
                (db.select(db.billingCycles)).get(),
                (db.select(db.lines)).get(),
                (db.select(db.customers)).get(),
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Text('تعذر تحميل بيانات التقرير. حاول مرة أخرى.');
                }
                if (!snapshot.hasData) return const SizedBox.shrink();

                final payments = (snapshot.data![0] as List<Payment>)
                    .where((payment) =>
                        !payment.isVoided &&
                        !payment.paidAt.isBefore(from) &&
                        !payment.paidAt.isAfter(to))
                    .toList()
                  ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
                final expenses = (snapshot.data![1] as List<Expense>)
                    .where((expense) =>
                        !expense.spentAt.isBefore(from) &&
                        !expense.spentAt.isAfter(to))
                    .toList();
                final cycles = snapshot.data![2] as List<BillingCycle>;
                final lines = snapshot.data![3] as List<Line>;
                final customers = snapshot.data![4] as List<Customer>;
                final linesById = {for (final line in lines) line.id: line};
                final customersById = {
                  for (final customer in customers) customer.id: customer
                };

                final total = payments.fold<int>(
                  0,
                  (sum, payment) => sum + payment.amountPiasters,
                );
                final expenseTotal = expenses.fold<int>(
                  0,
                  (sum, expense) => sum + expense.amountPiasters,
                );
                final currentMonth = YearMonth.nowCairo();
                final arrears = cycles
                    .where((cycle) =>
                        YearMonth(cycle.year, cycle.month)
                                .compareTo(currentMonth) <=
                            0)
                    .fold<int>(
                      0,
                      (sum, cycle) => sum +
                          (cycle.pricePiasters - cycle.paidPiasters)
                              .clamp(0, 1 << 62).toInt(),
                    );
                final partialCycles =
                    cycles.where((cycle) => cycle.status == 'partial').length;
                final prepaid = cycles
                    .where((cycle) =>
                        YearMonth(cycle.year, cycle.month).isFuture &&
                        cycle.status == 'paid')
                    .fold<int>(0, (sum, cycle) => sum + cycle.paidPiasters);
                final byMethod = <String, int>{};
                for (final payment in payments) {
                  byMethod[payment.method] =
                      (byMethod[payment.method] ?? 0) + payment.amountPiasters;
                }
                final activeLines = lines
                    .where((line) =>
                        line.status == 'active' && line.deletedAt == null)
                    .length;
                final exportRows = payments.map((payment) {
                  final line = linesById[payment.lineId];
                  final customer = customersById[payment.customerId];
                  return ExportRow(
                    customer?.name ?? 'عميل غير معروف',
                    line?.number ?? 'خط غير موجود',
                    payment.amountPiasters,
                    payment.paidAt,
                    payment.receiptNumber,
                  );
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _reportRow('إجمالي المدفوعات', Money.format(total)),
                    _reportRow('عدد عمليات الدفع', '${payments.length}'),
                    _reportRow(
                      'عدد العملاء الذين دفعوا',
                      '${payments.map((payment) => payment.customerId).toSet().length}',
                    ),
                    _reportRow('عدد الخطوط النشطة', '$activeLines'),
                    _reportRow('إجمالي المتأخرات حتى الشهر الحالي', Money.format(arrears)),
                    _reportRow('عدد الاشتراكات الجزئية', '$partialCycles'),
                    _reportRow('الاشتراكات المستقبلية المسددة', Money.format(prepaid)),
                    _reportRow('إجمالي المصروفات', Money.format(expenseTotal)),
                    _reportRow(
                      'صافي التحصيل بعد المصروفات المسجلة',
                      Money.format(total - expenseTotal),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'توزيع المدفوعات حسب طريقة الدفع',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...byMethod.entries.map(
                      (entry) => _reportRow(entry.key, Money.format(entry.value)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final file = await ExportService.exportPdf(
                          title: 'تقرير المدفوعات',
                          rows: exportRows,
                          total: total,
                        );
                        if (context.mounted) await ExportService.share(file);
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('تصدير PDF'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final file = await ExportService.exportExcel(
                          rows: exportRows,
                          total: total,
                        );
                        if (context.mounted) await ExportService.share(file);
                      },
                      icon: const Icon(Icons.table_chart),
                      label: const Text('تصدير Excel'),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'إضافة مصروف (اختياري)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextField(
                      controller: _expenseTitle,
                      decoration: const InputDecoration(labelText: 'اسم المصروف'),
                    ),
                    TextField(
                      controller: _expenseAmount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'المبلغ بالجنيه'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final amount = Money.parseEGP(_expenseAmount.text);
                        if (_expenseTitle.text.trim().isEmpty ||
                            amount == null ||
                            amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('أدخل اسم المصروف ومبلغاً صحيحاً'),
                            ),
                          );
                          return;
                        }
                        try {
                          await repos.addExpense(
                            title: _expenseTitle.text,
                            amountPiasters: amount,
                          );
                          if (!mounted) return;
                          setState(() {
                            _expenseTitle.clear();
                            _expenseAmount.clear();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم حفظ المصروف')),
                          );
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر حفظ المصروف: $error')),
                          );
                        }
                      },
                      child: const Text('حفظ المصروف'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'سجل المدفوعات خلال الفترة',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...payments.map((payment) {
                      final line = linesById[payment.lineId];
                      final customer = customersById[payment.customerId];
                      return Card(
                        child: ListTile(
                          title: Text(Money.format(payment.amountPiasters)),
                          subtitle: Text(
                            '${customer?.name ?? 'عميل غير معروف'} — ${line?.number ?? 'خط غير موجود'}\n'
                            '${payment.paidAt.day}/${payment.paidAt.month}/${payment.paidAt.year} — ${payment.receiptNumber}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(String title, String value) => Card(
        child: ListTile(
          title: Text(title),
          trailing: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
}
