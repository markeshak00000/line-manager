import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../services/export_service.dart';
import '../lines/line_detail_screen.dart';
import '../lines/line_form.dart';
import '../payments/payment_form.dart';

class CustomerDetailScreen extends StatelessWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final repos = context.read<Repos>();
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير كشف حساب PDF',
            onPressed: () => _exportStatement(context, db, customer),
          ),
        ],
      ),
      body: FutureBuilder<List<Line>>(
        future: repos.linesForCustomer(customer.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل بيانات العميل: ${snapshot.error}'));
          }
          final lines = snapshot.data ?? const <Line>[];
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
                        customer.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(customer.phone ?? 'بدون رقم تواصل'),
                      if (customer.whatsapp != null) Text('واتساب: ${customer.whatsapp}'),
                      if (customer.address != null) Text(customer.address!),
                      if (customer.notes != null) Text('ملاحظات: ${customer.notes!}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'الخطوط (${lines.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (lines.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد خطوط لهذا العميل بعد.'),
                  ),
                ),
              ...lines.map(
                (line) => Card(
                  child: ListTile(
                    title: Text(line.number),
                    subtitle: Text(
                      '${line.carrier} — ${_lineTypeLabel(line.lineType)} — ${_statusLabel(line.status)}'
                      '${line.creditPiasters > 0 ? ' — رصيد مقدم ${Money.format(line.creditPiasters)}' : ''}',
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => LineDetailScreen(line: line)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LineFormScreen(customer: customer)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('إضافة خط جديد'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openPayment(context, customer, lines),
                icon: const Icon(Icons.payments),
                label: const Text('تسجيل دفعة'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPayment(
    BuildContext context,
    Customer targetCustomer,
    List<Line> lines,
  ) async {
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف خطًا للعميل أولًا')),
      );
      return;
    }

    Line? selected = lines.length == 1 ? lines.first : null;
    if (selected == null) {
      selected = await showModalBottomSheet<Line>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('اختر الخط الذي تريد تسجيل الدفعة له')),
              ...lines.map(
                (line) => ListTile(
                  leading: const Icon(Icons.sim_card),
                  title: Text(line.number),
                  subtitle: Text(_statusLabel(line.status)),
                  onTap: () => Navigator.pop(sheetContext, line),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final chosenLine = selected;
    if (chosenLine == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          preselectedCustomer: targetCustomer,
          preselectedLine: chosenLine,
        ),
      ),
    );
  }

  Future<void> _exportStatement(
    BuildContext context,
    AppDatabase db,
    Customer target,
  ) async {
    try {
      final payments = await (db.select(db.payments)
            ..where((payment) =>
                payment.customerId.equals(target.id) &
                payment.isVoided.equals(false))
            ..orderBy([(payment) => OrderingTerm(expression: payment.paidAt)]))
          .get();
      final lines = await (db.select(db.lines)
            ..where((line) => line.customerId.equals(target.id)))
          .get();
      final linesById = {for (final line in lines) line.id: line};
      final rows = payments
          .map(
            (payment) => ExportRow(
              target.name,
              linesById[payment.lineId]?.number ?? 'خط غير موجود',
              payment.amountPiasters,
              payment.paidAt,
              payment.receiptNumber,
            ),
          )
          .toList();
      final total = rows.fold<int>(0, (sum, row) => sum + row.amount);
      final file = await ExportService.exportPdf(
        title: 'كشف حساب — ${target.name}',
        rows: rows,
        total: total,
      );
      if (context.mounted) await ExportService.share(file);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تصدير كشف الحساب: $error')),
      );
    }
  }

  static String _lineTypeLabel(String value) => switch (value) {
        'calls' => 'مكالمات',
        'internet' => 'إنترنت',
        'business' => 'شركات',
        _ => 'أخرى',
      };

  static String _statusLabel(String value) => switch (value) {
        'active' => 'نشط',
        'paused' => 'متوقف مؤقتًا',
        'cancelled' => 'ملغي',
        _ => value,
      };
}
