import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../services/notification_service.dart';
import '../payments/payment_form.dart';
import 'line_form.dart';

class LineDetailScreen extends StatelessWidget {
  final Line line;

  const LineDetailScreen({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final repos = context.read<Repos>();
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: Text(line.number),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تعديل الخط',
            onPressed: () => _openEditLine(context, db, line),
          ),
        ],
      ),
      body: FutureBuilder<List<BillingCycle>>(
        future: repos.cyclesForLine(line.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل بيانات الخط: ${snapshot.error}'));
          }

          final cycles = snapshot.data ?? const <BillingCycle>[];
          final paid = cycles.fold<int>(0, (sum, cycle) => sum + cycle.paidPiasters);
          final now = YearMonth.nowCairo();
          final arrears = cycles
              .where((cycle) => YearMonth(cycle.year, cycle.month).compareTo(now) <= 0)
              .fold<int>(
                0,
                (sum, cycle) =>
                    sum + (cycle.pricePiasters - cycle.paidPiasters).clamp(0, 1 << 62).toInt(),
              );
          final currentCycles = cycles
              .where((cycle) => cycle.year == now.year && cycle.month == now.month)
              .toList();
          final nextDueMonth = now.next();
          final nextDue = DateTime(nextDueMonth.year, nextDueMonth.month, 1);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.number,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      Text('${line.carrier} — ${_lineTypeLabel(line.lineType)} — ${_statusLabel(line.status)}'),
                      const SizedBox(height: 8),
                      Text('إجمالي المدفوع: ${Money.format(paid)}'),
                      Text('المتأخرات حتى الشهر الحالي: ${Money.format(arrears)}'),
                      if (line.creditPiasters > 0)
                        Text(
                          'رصيد مقدم غير موزع: ${Money.format(line.creditPiasters)}',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      Text(
                        'الشهر الحالي: ${now.labelAr} — '
                        '${currentCycles.isEmpty ? 'لم يُنشأ الاستحقاق بعد' : _cycleStatusLabel(currentCycles.first.status)}',
                      ),
                      Text('موعد الاستحقاق التالي: ${_dateLabel(nextDue)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'سجل الاشتراكات الشهرية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ...cycles.reversed.map((cycle) {
                final month = YearMonth(cycle.year, cycle.month);
                final future = month.isFuture;
                final remaining = (cycle.pricePiasters - cycle.paidPiasters).clamp(0, 1 << 62).toInt();
                return Card(
                  child: ListTile(
                    title: Text('${month.labelAr}${future ? ' — مستقبلي' : ''}'),
                    subtitle: Text(
                      'السعر ${Money.format(cycle.pricePiasters)} — '
                      'المدفوع ${Money.format(cycle.paidPiasters)} — '
                      'المتبقي ${Money.format(remaining)}\n'
                      'الباقة: ${cycle.packageNameSnapshot}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      _cycleStatusLabel(cycle.status),
                      style: TextStyle(
                        color: cycle.status == 'paid' ? Colors.green : Colors.deepOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final customer = await (db.select(db.customers)
                        ..where((item) => item.id.equals(line.customerId)))
                      .getSingleOrNull();
                  if (!context.mounted || customer == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentFormScreen(
                        preselectedCustomer: customer,
                        preselectedLine: line,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.payments),
                label: const Text('تسجيل دفعة لهذا الخط'),
              ),
              const SizedBox(height: 8),
              if (line.status == 'active')
                OutlinedButton.icon(
                  onPressed: () => _pauseLine(context, repos, db, line),
                  icon: const Icon(Icons.pause),
                  label: const Text('إيقاف الخط مؤقتًا'),
                ),
              if (line.status == 'paused')
                OutlinedButton.icon(
                  onPressed: () => _reactivateLine(context, repos, db, line),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('إعادة تنشيط الخط'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pauseLine(
    BuildContext context,
    Repos repos,
    AppDatabase db,
    Line target,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إيقاف الخط؟'),
        content: const Text(
          'سيتوقف إنشاء الاستحقاقات المستقبلية. لن تُحذف المدفوعات أو الإيصالات أو التاريخ المالي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repos.updateLine(id: target.id, status: 'paused');
      await NotificationService.refreshAll(db);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إيقاف الخط مؤقتًا مع الاحتفاظ بتاريخه المالي')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إيقاف الخط: $error')),
      );
    }
  }

  Future<void> _reactivateLine(
    BuildContext context,
    Repos repos,
    AppDatabase db,
    Line target,
  ) async {
    try {
      await repos.updateLine(id: target.id, status: 'active');
      await repos.ensureCyclesForAllActiveLines();
      await NotificationService.refreshAll(db);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تنشيط الخط من الشهر الحالي')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنشيط الخط: $error')),
      );
    }
  }

  Future<void> _openEditLine(BuildContext context, AppDatabase db, Line target) async {
    final customer = await (db.select(db.customers)
          ..where((row) => row.id.equals(target.customerId)))
        .getSingleOrNull();
    if (!context.mounted || customer == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LineFormScreen(customer: customer, existing: target),
      ),
    );
  }

  static String _dateLabel(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';

  static String _statusLabel(String value) => switch (value) {
        'active' => 'نشط',
        'paused' => 'متوقف مؤقتًا',
        'cancelled' => 'ملغي',
        _ => value,
      };

  static String _cycleStatusLabel(String value) => switch (value) {
        'paid' => 'مدفوع بالكامل',
        'partial' => 'دفع جزئي',
        _ => 'لم يدفع',
      };

  static String _lineTypeLabel(String value) => switch (value) {
        'calls' => 'مكالمات',
        'internet' => 'إنترنت',
        'business' => 'شركات',
        _ => 'أخرى',
      };
}
