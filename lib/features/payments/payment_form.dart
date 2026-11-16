import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../services/notification_service.dart';
import '../../services/receipt_service.dart';
import '../../services/whatsapp_service.dart';

class PaymentFormScreen extends StatefulWidget {
  final Customer? preselectedCustomer;
  final Line? preselectedLine;

  const PaymentFormScreen({
    super.key,
    this.preselectedCustomer,
    this.preselectedLine,
  });

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  String _query = '';
  Line? _line;
  Customer? _customer;
  Package? _package;
  bool _loadingLine = false;
  bool _saving = false;
  bool _autoSuggestAmount = true;
  String _method = 'cash';
  final Set<String> _selectedMonths = {};
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _collectorController = TextEditingController(text: 'ماما');

  List<YearMonth> get _months {
    final now = YearMonth.nowCairo();
    return List.generate(36, (index) => now.addMonths(index - 24));
  }

  @override
  void initState() {
    super.initState();
    _line = widget.preselectedLine;
    _customer = widget.preselectedCustomer;
    _loadCollector();
    if (_line != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSelectedLine());
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _collectorController.dispose();
    super.dispose();
  }

  Future<void> _loadCollector() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('collector_name');
    if (mounted && saved != null && saved.trim().isNotEmpty) {
      _collectorController.text = saved.trim();
    }
  }

  Future<void> _loadSelectedLine() async {
    final line = _line;
    if (line == null || !mounted) return;
    setState(() => _loadingLine = true);
    try {
      final db = context.read<AppDatabase>();
      final package = await (db.select(db.packages)
            ..where((row) => row.id.equals(line.packageId)))
          .getSingleOrNull();
      final customer = _customer ?? await (db.select(db.customers)
            ..where((row) => row.id.equals(line.customerId)))
          .getSingleOrNull();
      if (!mounted) return;
      setState(() {
        _package = package;
        _customer = customer;
        _loadingLine = false;
      });
      await _suggestAmount();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingLine = false);
      _showMessage('تعذر تحميل بيانات الخط: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.read<Repos>();
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دفعة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_line == null) ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'ابحث باسم العميل أو رقم الخط أو رقم الهاتف',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              if (_query.trim().isNotEmpty)
                FutureBuilder<List<SearchHit>>(
                  future: repos.globalSearch(_query),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return const ListTile(title: Text('تعذر تنفيذ البحث'));
                    }
                    final hits = snapshot.data ?? const <SearchHit>[];
                    if (hits.isEmpty) {
                      return const ListTile(title: Text('لا توجد نتائج'));
                    }
                    return Column(
                      children: hits
                          .map(
                            (hit) => Card(
                              child: ListTile(
                                leading: Icon(
                                  hit.type == 'line'
                                      ? Icons.sim_card
                                      : hit.type == 'payment'
                                          ? Icons.receipt_long
                                          : Icons.person,
                                ),
                                title: Text(hit.title),
                                subtitle: Text(hit.subtitle),
                                onTap: () => _selectSearchHit(hit),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
            ],
            if (_line != null) _selectedLineCard(),
            if (_loadingLine) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text(
              'اختر الشهور المطلوب سدادها',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _months.map((month) {
                final selected = _selectedMonths.contains(month.key);
                return FilterChip(
                  label: Text(month.labelAr),
                  selected: selected,
                  onSelected: _line == null || _loadingLine
                      ? null
                      : (value) async {
                          setState(() {
                            if (value) {
                              _selectedMonths.add(month.key);
                            } else {
                              _selectedMonths.remove(month.key);
                            }
                          });
                          await _suggestAmount();
                        },
                );
              }).toList(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  setState(_selectedMonths.clear);
                  await _suggestAmount();
                },
                child: const Text('مسح اختيار الشهور'),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                _quickChip('شهر واحد', 1),
                _quickChip('شهرين', 2),
                _quickChip('3 شهور', 3),
                _quickChip('6 شهور', 6),
                _quickChip('12 شهراً', 12),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _autoSuggestAmount = false,
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع بالجنيه *',
                hintText: 'مثال: 250 أو 250.50',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('نقدًا')),
                DropdownMenuItem(value: 'instapay', child: Text('إنستاباي')),
                DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                DropdownMenuItem(value: 'wallet', child: Text('محفظة إلكترونية')),
                DropdownMenuItem(value: 'other', child: Text('طريقة أخرى')),
              ],
              onChanged: (value) => setState(() => _method = value ?? 'cash'),
            ),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(labelText: 'رقم مرجعي للتحويل (اختياري)'),
            ),
            TextField(
              controller: _collectorController,
              decoration: const InputDecoration(labelText: 'اسم المحصّل'),
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _saving || _loadingLine ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الدفعة'),
            ),
            const SizedBox(height: 8),
            const Text(
              'يتم توزيع المبلغ على أقدم شهر مختار أولًا. أي زيادة عن قيمة الشهور المختارة تُسجّل كرصد مقدم منفصل على الخط.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedLineCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('العميل: ${_customer?.name ?? '...'}'),
              Text('الخط: ${_line!.number}'),
              Text(
                'الباقة: ${_package?.name ?? '...'} — السعر: ${Money.format(_package?.pricePiasters ?? 0)}',
              ),
              if (_line!.creditPiasters > 0)
                Text(
                  'رصيد مقدم غير موزع: ${Money.format(_line!.creditPiasters)}',
                  style: const TextStyle(color: Colors.green),
                ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _line = null;
                  _customer = widget.preselectedCustomer;
                  _package = null;
                  _query = '';
                  _selectedMonths.clear();
                  _amountController.clear();
                }),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('تغيير الخط'),
              ),
            ],
          ),
        ),
      );

  Widget _quickChip(String label, int count) => ActionChip(
        label: Text(label),
        onPressed: _line == null || _package == null || _loadingLine
            ? null
            : () async {
                final now = YearMonth.nowCairo();
                final selected = List.generate(count, (index) => now.addMonths(index));
                setState(() {
                  _selectedMonths
                    ..clear()
                    ..addAll(selected.map((month) => month.key));
                  _autoSuggestAmount = true;
                });
                await _suggestAmount(force: true);
              },
      );

  Future<void> _suggestAmount({bool force = false}) async {
    if (_line == null || _package == null) return;
    if (!_autoSuggestAmount && !force) return;
    if (_selectedMonths.isEmpty) {
      if (mounted) _amountController.clear();
      return;
    }

    final repos = context.read<Repos>();
    final existing = await repos.cyclesForLine(_line!.id);
    final existingByKey = {
      for (final cycle in existing) '${cycle.year}-${cycle.month.toString().padLeft(2, '0')}': cycle,
    };
    var due = 0;
    final months = _selectedMonths.map((key) {
      final parts = key.split('-');
      return YearMonth(int.parse(parts[0]), int.parse(parts[1]));
    }).toList()
      ..sort((a, b) => a.compareTo(b));

    for (final month in months) {
      final cycle = existingByKey[month.key];
      if (cycle != null) {
        due += (cycle.pricePiasters - cycle.paidPiasters).clamp(0, 1 << 62).toInt();
      } else {
        due += await repos.priceForMonth(_line!.packageId, month);
      }
    }

    if (!mounted || (!_autoSuggestAmount && !force)) return;
    _amountController.text = Money.format(due).replaceAll(' ج.م', '');
  }

  Future<void> _selectSearchHit(SearchHit hit) async {
    final db = context.read<AppDatabase>();
    Line? selectedLine;

    if (hit.lineId != null) {
      selectedLine = await (db.select(db.lines)
            ..where((row) => row.id.equals(hit.lineId!)))
          .getSingleOrNull();
    } else if (hit.paymentId != null) {
      final payment = await (db.select(db.payments)
            ..where((row) => row.id.equals(hit.paymentId!)))
          .getSingleOrNull();
      if (payment != null) {
        selectedLine = await (db.select(db.lines)
              ..where((row) => row.id.equals(payment.lineId)))
            .getSingleOrNull();
      }
    } else if (hit.customerId != null) {
      final lines = await context.read<Repos>().linesForCustomer(hit.customerId!);
      if (lines.isEmpty) {
        if (mounted) _showMessage('هذا العميل ليس لديه خطوط مسجلة');
        return;
      }
      if (lines.length == 1) {
        selectedLine = lines.first;
      } else {
        selectedLine = await showModalBottomSheet<Line>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('اختر الخط المطلوب تحصيله')),
                ...lines.map(
                  (item) => ListTile(
                    leading: const Icon(Icons.sim_card),
                    title: Text(item.number),
                    subtitle: Text(item.status == 'active' ? 'نشط' : 'متوقف'),
                    onTap: () => Navigator.pop(sheetContext, item),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (selectedLine == null || !mounted) return;
    final customer = await (db.select(db.customers)
          ..where((row) => row.id.equals(selectedLine!.customerId)))
        .getSingleOrNull();
    if (!mounted) return;

    setState(() {
      _line = selectedLine;
      _customer = customer;
      _package = null;
      _selectedMonths.clear();
      _amountController.clear();
      _query = '';
      _autoSuggestAmount = true;
    });
    await _loadSelectedLine();
  }

  Future<void> _save() async {
    if (_line == null || _customer == null || _package == null) {
      _showMessage('اختر العميل والخط أولًا');
      return;
    }
    if (_selectedMonths.isEmpty) {
      _showMessage('اختر شهرًا واحدًا على الأقل');
      return;
    }

    final amountPiasters = Money.parseEGP(_amountController.text);
    if (amountPiasters == null || amountPiasters <= 0) {
      _showMessage('أدخل مبلغًا صحيحًا حتى منزلتين عشريتين');
      return;
    }

    setState(() => _saving = true);
    var paymentSaved = false;
    try {
      final months = _selectedMonths.map((key) {
        final parts = key.split('-');
        return YearMonth(int.parse(parts[0]), int.parse(parts[1]));
      }).toList()
        ..sort((a, b) => a.compareTo(b));

      final collector = _collectorController.text.trim().isEmpty
          ? 'ماما'
          : _collectorController.text.trim();
      final line = _line!;
      final customer = _customer!;
      final package = _package!;
      final repos = context.read<Repos>();
      final cyclesBeforePayment = await repos.cyclesForLine(line.id);
      final cyclesBeforeByKey = {
        for (final cycle in cyclesBeforePayment)
          '${cycle.year}-${cycle.month.toString().padLeft(2, '0')}': cycle,
      };
      var outstandingBeforePayment = 0;
      for (final month in months) {
        final previous = cyclesBeforeByKey[month.key];
        outstandingBeforePayment += previous == null
            ? await repos.priceForMonth(line.packageId, month)
            : (previous.pricePiasters - previous.paidPiasters)
                .clamp(0, 1 << 62)
                .toInt();
      }
      final result = await repos.recordPayment(
            lineId: line.id,
            customerId: customer.id,
            amountPiasters: amountPiasters,
            months: months,
            method: _method,
            reference: _referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            collector: collector,
            idempotencyKey: const Uuid().v4(),
          );
      paymentSaved = true;

      final cycles = await repos.cyclesForLine(line.id);
      final selectedCycles = cycles.where((cycle) => months.any(
            (month) => month.year == cycle.year && month.month == cycle.month,
          ));
      final remaining = selectedCycles.fold<int>(
        0,
        (sum, cycle) =>
            sum + (cycle.pricePiasters - cycle.paidPiasters).clamp(0, 1 << 62).toInt(),
      );
      final arrears = await repos.arrearsForLine(line.id);
      final currentMonth = YearMonth.nowCairo();
      final currentAndFutureCycles = cycles
          .where((cycle) =>
              YearMonth(cycle.year, cycle.month).compareTo(currentMonth) >= 0)
          .toList()
        ..sort((a, b) =>
            YearMonth(a.year, a.month).compareTo(YearMonth(b.year, b.month)));
      final unpaidUpcoming = currentAndFutureCycles.where(
        (cycle) => cycle.paidPiasters < cycle.pricePiasters,
      );
      final nextMonth = unpaidUpcoming.isNotEmpty
          ? YearMonth(unpaidUpcoming.first.year, unpaidUpcoming.first.month)
          : (currentAndFutureCycles.isNotEmpty
              ? YearMonth(
                  currentAndFutureCycles.last.year,
                  currentAndFutureCycles.last.month,
                ).next()
              : currentMonth.next());
      final lineAfterPayment = await (context.read<AppDatabase>().select(context.read<AppDatabase>().lines)
            ..where((row) => row.id.equals(line.id)))
          .getSingle();

      final receipt = ReceiptData(
        receiptNumber: result.receiptNumber,
        paidAt: DateTime.now(),
        customer: customer.name,
        lineNumber: line.number,
        carrier: line.carrier,
        lineType: line.lineType,
        packageName: package.name,
        monthlyPrice: package.pricePiasters,
        months: months.map((month) => month.labelAr).toList(),
        totalDue: outstandingBeforePayment,
        paid: amountPiasters,
        remaining: remaining,
        creditPiasters: lineAfterPayment.creditPiasters,
        method: _method,
        status: remaining == 0 ? 'مسدد بالكامل' : 'سداد جزئي',
        nextDue: DateTime(nextMonth.year, nextMonth.month, 1),
        totalArrears: arrears,
        collector: collector,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      await NotificationService.refreshAll(context.read<AppDatabase>());

      FileShareResult shareResult = FileShareResult.notRequested;
      try {
        final imageFile = await ReceiptService.renderPng(receipt);
        if (!mounted) return;
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تم تسجيل الدفعة'),
            content: Text(
              'المبلغ المدفوع: ${Money.format(amountPiasters)}\n'
              'المتبقي على الشهور المختارة: ${Money.format(remaining)}\n'
              'رقم الإيصال: ${result.receiptNumber}\n\n'
              'هل تريد مشاركة صورة الإيصال؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('لاحقًا'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('مشاركة الإيصال'),
              ),
            ],
          ),
        );
        if (shouldShare == true) {
          await WhatsAppService.shareReceipt(
            imageFile,
            whatsappNumber: customer.whatsapp ?? customer.phone,
            caption: 'إيصال الدفع — ${customer.name} — ${line.number} — ${result.receiptNumber}',
          );
          shareResult = FileShareResult.shared;
        }
      } catch (error) {
        shareResult = FileShareResult.failed;
        if (mounted) _showMessage('تم حفظ الدفعة، لكن تعذر تجهيز أو مشاركة الإيصال: $error');
      }

      if (!mounted) return;
      if (shareResult == FileShareResult.notRequested) {
        _showMessage('تم تسجيل الدفعة بنجاح. رقم الإيصال: ${result.receiptNumber}');
      } else if (shareResult == FileShareResult.shared) {
        _showMessage('تم تسجيل الدفعة. اختر جهة الاتصال واضغط إرسال من واتساب.');
      }

      Navigator.of(context).maybePop();
    } catch (error) {
      _showMessage(
        paymentSaved
            ? 'تم تسجيل الدفعة، لكن حدثت مشكلة بعد الحفظ: $error'
            : 'تعذر تسجيل الدفعة: $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

enum FileShareResult { notRequested, shared, failed }
