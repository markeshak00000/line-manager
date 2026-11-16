import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/year_month.dart';

class ReceiptData {
  final String receiptNumber;
  final DateTime paidAt;
  final String customer;
  final String lineNumber;
  final String carrier;
  final String lineType;
  final String packageName;
  final int monthlyPrice;
  final List<String> months;
  final int totalDue;
  final int paid;
  final int remaining;
  final int creditPiasters;
  final String method;
  final String status;
  final DateTime nextDue;
  final int totalArrears;
  final String collector;
  final String? notes;

  const ReceiptData({
    required this.receiptNumber,
    required this.paidAt,
    required this.customer,
    required this.lineNumber,
    required this.carrier,
    required this.lineType,
    required this.packageName,
    required this.monthlyPrice,
    required this.months,
    required this.totalDue,
    required this.paid,
    required this.remaining,
    this.creditPiasters = 0,
    required this.method,
    required this.status,
    required this.nextDue,
    required this.totalArrears,
    required this.collector,
    this.notes,
  });
}

class ReceiptService {
  static String _money(int piasters) {
    final negative = piasters < 0;
    final value = piasters.abs();
    final pounds = value ~/ 100;
    final fraction = value % 100;
    final amount = fraction == 0
        ? '$pounds'
        : '$pounds.${fraction.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}$amount ج.م';
  }

  static String _methodLabel(String value) => switch (value) {
        'cash' => 'نقدًا',
        'instapay' => 'إنستاباي',
        'bank' => 'تحويل بنكي',
        'wallet' => 'محفظة إلكترونية',
        _ => 'طريقة أخرى',
      };

  static String _lineTypeLabel(String value) => switch (value) {
        'calls' => 'مكالمات',
        'internet' => 'إنترنت',
        'business' => 'شركات',
        _ => 'أخرى',
      };

  static Future<File> renderPng(ReceiptData data) async {
    const width = 1080.0;
    const padding = 56.0;
    const headerHeight = 190.0;
    const footerHeight = 110.0;
    const labelWidth = 360.0;
    const valueWidth = width - (padding * 2) - labelWidth - 24;

    final rows = <(String, String, bool)>[
      ('رقم الإيصال', data.receiptNumber, true),
      (
        'التاريخ والوقت',
        '${_date(data.paidAt)} — ${data.paidAt.hour.toString().padLeft(2, '0')}:${data.paidAt.minute.toString().padLeft(2, '0')}',
        false,
      ),
      ('اسم العميل', data.customer, false),
      ('رقم الخط', data.lineNumber, true),
      ('الشركة ونوع الخط', '${data.carrier} — ${_lineTypeLabel(data.lineType)}', false),
      ('الباقة', data.packageName, false),
      ('السعر الشهري الحالي', _money(data.monthlyPrice), false),
      ('الشهور المختارة', data.months.join('، '), false),
      ('المستحق قبل هذه الدفعة', _money(data.totalDue), false),
      ('المبلغ المدفوع في العملية', _money(data.paid), true),
      ('المتبقي على الشهور المختارة', _money(data.remaining), true),
      if (data.creditPiasters > 0)
        ('رصيد مقدم غير موزع', _money(data.creditPiasters), true),
      ('طريقة الدفع', _methodLabel(data.method), false),
      ('حالة السداد', data.status, true),
      ('الاستحقاق التالي', _date(data.nextDue), false),
      ('إجمالي متأخرات الخط', _money(data.totalArrears), false),
      ('استلم من / المحصّل', data.collector, false),
      if (data.notes != null && data.notes!.trim().isNotEmpty)
        ('ملاحظات', data.notes!.trim(), false),
    ];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final preparedRows = <(String, ui.Paragraph, ui.Paragraph, double, bool)>[];
    var contentHeight = 0.0;

    for (final row in rows) {
      final label = _paragraph(
        row.$1,
        width: labelWidth,
        fontSize: 26,
        color: const Color(0xFF5F6368),
        bold: false,
      );
      final value = _paragraph(
        row.$2,
        width: valueWidth,
        fontSize: 28,
        color: row.$3 ? const Color(0xFF202124) : const Color(0xFF303134),
        bold: row.$3,
      );
      final rowHeight = (label.height > value.height ? label.height : value.height) + 34;
      preparedRows.add((row.$1, label, value, rowHeight, row.$3));
      contentHeight += rowHeight;
    }

    final height = headerHeight + contentHeight + footerHeight + 40;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, width, headerHeight),
        const Radius.circular(0),
      ),
      Paint()..color = const Color(0xFFFF6B00),
    );

    final headerTitle = _paragraph(
      'إدارة خطوط العملاء',
      width: width - padding * 2,
      fontSize: 48,
      color: Colors.white,
      bold: true,
      align: TextAlign.center,
    );
    final headerSubtitle = _paragraph(
      'إيصال تحصيل — صادر عن نشاط صاحبة التطبيق وليس عن شركة Orange',
      width: width - padding * 2,
      fontSize: 25,
      color: Colors.white,
      align: TextAlign.center,
    );
    canvas.drawParagraph(headerTitle, Offset(padding, 32));
    canvas.drawParagraph(headerSubtitle, Offset(padding, 112));

    var y = headerHeight + 24.0;
    for (final row in preparedRows) {
      final rowHeight = row.$4;
      final valueX = padding;
      final labelX = padding + valueWidth + 24;
      canvas.drawParagraph(row.$3, Offset(valueX, y + 8));
      canvas.drawParagraph(row.$2, Offset(labelX, y + 8));
      y += rowHeight;
      canvas.drawLine(
        Offset(padding, y - 8),
        Offset(width - padding, y - 8),
        Paint()
          ..color = const Color(0xFFEEEEEE)
          ..strokeWidth = 2,
      );
    }

    final footer = _paragraph(
      'شكرًا لكم — للاحتفاظ بالإيصال يُرجى حفظ هذه الصورة',
      width: width - padding * 2,
      fontSize: 24,
      color: const Color(0xFF5F6368),
      align: TextAlign.center,
    );
    canvas.drawParagraph(footer, Offset(padding, y + 16));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (byteData == null) throw StateError('تعذر إنشاء صورة الإيصال');

    final directory = await getTemporaryDirectory();
    final safeName = data.receiptNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${directory.path}/receipt_$safeName.png');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file;
  }

  static ui.Paragraph _paragraph(
    String text, {
    required double width,
    required double fontSize,
    required Color color,
    bool bold = false,
    TextAlign align = TextAlign.right,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: TextDirection.rtl,
        textAlign: align,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        maxLines: null,
      ),
    )
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    return paragraph;
  }

  static String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';

  static DateTime nextDueFor(YearMonth month) {
    final next = month.next();
    return DateTime(next.year, next.month, 1);
  }
}
