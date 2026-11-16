import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/validation.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../services/notification_service.dart';

class LineFormScreen extends StatefulWidget {
  final Customer customer;
  final Line? existing;

  const LineFormScreen({
    super.key,
    required this.customer,
    this.existing,
  });

  @override
  State<LineFormScreen> createState() => _LineFormScreenState();
}

class _LineFormScreenState extends State<LineFormScreen> {
  final _number = TextEditingController();
  final _owner = TextEditingController();
  final _notes = TextEditingController();
  String? _packageId;
  String _type = 'calls';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _number.text = existing.number;
      _owner.text = existing.ownerName ?? '';
      _notes.text = existing.notes ?? '';
      _packageId = existing.packageId;
      _type = existing.lineType;
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _owner.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final repos = context.read<Repos>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'خط جديد — ${widget.customer.name}'
              : 'تعديل الخط — ${widget.existing!.number}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _number,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الخط *',
              hintText: '01XXXXXXXXX',
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Package>>(
            future: (db.select(db.packages)..where((p) => p.deletedAt.isNull())).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return const Text('تعذر تحميل الباقات');
              }
              final available = (snapshot.data ?? const <Package>[])
                  .where((item) =>
                      !item.isArchived || item.id == widget.existing?.packageId)
                  .toList();
              return DropdownButtonFormField<String>(
                value: available.any((item) => item.id == _packageId)
                    ? _packageId
                    : null,
                hint: const Text('اختر الباقة *'),
                decoration: const InputDecoration(labelText: 'الباقة'),
                items: available
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.name} — ${Money.format(item.pricePiasters)}'
                          '${item.isArchived ? ' (مؤرشفة — للخط الحالي)' : ''}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving ? null : (value) => setState(() => _packageId = value),
              );
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'نوع الخط'),
            items: const [
              DropdownMenuItem(value: 'calls', child: Text('مكالمات')),
              DropdownMenuItem(value: 'internet', child: Text('إنترنت')),
              DropdownMenuItem(value: 'business', child: Text('شركات')),
              DropdownMenuItem(value: 'other', child: Text('أخرى')),
            ],
            onChanged: _saving ? null : (value) => setState(() => _type = value ?? 'calls'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _owner,
            decoration: const InputDecoration(labelText: 'اسم صاحب الخط (اختياري)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _save(context, repos, db),
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الخط'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, Repos repos, AppDatabase db) async {
    final validationError = Validation.lineNumber(_number.text);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }
    final packageId = _packageId;
    if (packageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الباقة أولًا')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final normalizedNumber = Validation.normalizeLine(_number.text);
      if (widget.existing == null) {
        await repos.addLine(
          customerId: widget.customer.id,
          packageId: packageId,
          number: normalizedNumber,
          type: _type,
          owner: _owner.text,
          notes: _notes.text,
          start: YearMonth.nowCairo(),
        );
      } else {
        await repos.updateLine(
          id: widget.existing!.id,
          number: normalizedNumber,
          packageId: packageId,
          lineType: _type,
          ownerName: _owner.text,
          notes: _notes.text,
          clearOwnerName: _owner.text.trim().isEmpty,
          clearNotes: _notes.text.trim().isEmpty,
        );
      }
      await repos.ensureCyclesForAllActiveLines();
      await NotificationService.refreshAll(db);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existing == null ? 'تم إضافة الخط بنجاح' : 'تم تعديل الخط'),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الخط: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
