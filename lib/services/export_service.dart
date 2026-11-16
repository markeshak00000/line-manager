import 'dart:io';
import 'dart:ui' as ui;

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class ExportRow {
  final String customer;
  final String line;
  final int amount;
  final DateTime date;
  final String receipt;

  const ExportRow(
    this.customer,
    this.line,
    this.amount,
    this.date,
    this.receipt,
  );
}

class ExportService {
  /// Renders Arabic text with Flutter's text engine into page images, then
  /// embeds those images in the PDF. This avoids relying on PDF base fonts,
  /// which do not contain Arabic glyphs or shaping.
  static Future<File> exportPdf({
    required String title,
    required List<ExportRow> rows,
    required int total,
  }) async {
    final document = pw.Document();
    const pageWidth = 1240.0;
    const pageHeight = 1754.0;
    const headerHeight = 190.0;
    const rowHeight = 66.0;
    const pageRows = 21;
    final chunks = <List<ExportRow>>[];
    if (rows.isEmpty) {
      chunks.add(const []);
    } else {
      for (var index = 0; index < rows.length; index += pageRows) {
        final end = (index + pageRows < rows.length)
            ? index + pageRows
            : rows.length;
        chunks.add(rows.sublist(index, end));
      }
    }

    for (var pageIndex = 0; pageIndex < chunks.length; pageIndex++) {
      final pageRowsData = chunks[pageIndex];
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, pageWidth, pageHeight),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, pageWidth, headerHeight),
        ui.Paint()..color = const ui.Color(0xFFFF6B00),
      );

      _drawText(
        canvas,
        title,
        x: 60,
        y: 42,
        width: pageWidth - 120,
        size: 48,
        color: const ui.Color(0xFFFFFFFF),
        bold: true,
      );
      _drawText(
        canvas,
        'تقرير إدارة خطوط العملاء — صفحة ${pageIndex + 1} من ${chunks.length}',
        x: 60,
        y: 112,
        width: pageWidth - 120,
        size: 26,
        color: const ui.Color(0xFFFFFFFF),
      );

      var y = headerHeight + 30;
      for (var index = 0; index < pageRowsData.length; index++) {
        final row = pageRowsData[index];
        if (index.isEven) {
          canvas.drawRRect(
            ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTWH(48, y, pageWidth - 96, rowHeight - 5),
              const ui.Radius.circular(12),
            ),
            ui.Paint()..color = const ui.Color(0xFFF5F6F8),
          );
        }
        final firstLine = '${row.customer} — ${row.line}';
        final secondLine =
            'المبلغ: ${_formatMoney(row.amount)}   التاريخ: ${row.date.day}/${row.date.month}/${row.date.year}   الإيصال: ${row.receipt}';
        _drawText(
          canvas,
          firstLine,
          x: 72,
          y: y + 6,
          width: pageWidth - 144,
          size: 25,
          color: const ui.Color(0xFF202124),
          bold: true,
        );
        _drawText(
          canvas,
          secondLine,
          x: 72,
          y: y + 35,
          width: pageWidth - 144,
          size: 22,
          color: const ui.Color(0xFF5F6368),
        );
        y += rowHeight;
      }

      if (pageIndex == chunks.length - 1) {
        final totalText = 'إجمالي المدفوعات: ${_formatMoney(total)}';
        _drawText(
          canvas,
          totalText,
          x: 60,
          y: pageHeight - 110,
          width: pageWidth - 120,
          size: 34,
          color: const ui.Color(0xFF202124),
          bold: true,
        );
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(pageWidth.toInt(), pageHeight.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('تعذر إنشاء صورة صفحة التقرير');
      }
      final png = byteData.buffer.asUint8List();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ),
      );
      image.dispose();
      picture.dispose();
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/line_manager_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  static Future<File> exportExcel({
    required List<ExportRow> rows,
    required int total,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['التقرير'];
    sheet.appendRow([
      TextCellValue('اسم العميل'),
      TextCellValue('رقم الخط'),
      TextCellValue('المبلغ بالجنيه'),
      TextCellValue('التاريخ'),
      TextCellValue('رقم الإيصال'),
    ]);
    for (final row in rows) {
      sheet.appendRow([
        TextCellValue(row.customer),
        TextCellValue(row.line),
        TextCellValue(_formatMoney(row.amount).replaceAll(' ج.م', '')),
        TextCellValue('${row.date.day}/${row.date.month}/${row.date.year}'),
        TextCellValue(row.receipt),
      ]);
    }
    sheet.appendRow([
      TextCellValue('الإجمالي'),
      TextCellValue(''),
      TextCellValue(_formatMoney(total).replaceAll(' ج.م', '')),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    final bytes = excel.save();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel');
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/line_manager_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> share(File file) async {
    if (!await file.exists()) throw ArgumentError('ملف التقرير غير موجود');
    await Share.shareXFiles([XFile(file.path)]);
  }

  static void _drawText(
    ui.Canvas canvas,
    String text, {
    required double x,
    required double y,
    required double width,
    required double size,
    ui.Color color = const ui.Color(0xFF202124),
    bool bold = false,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: ui.TextDirection.rtl,
        textAlign: ui.TextAlign.right,
        fontSize: size,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      ),
    )
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
  }

  static String _formatMoney(int piasters) {
    final pounds = piasters ~/ 100;
    final fraction = piasters.abs() % 100;
    return fraction == 0
        ? '$pounds ج.م'
        : '$pounds.${fraction.toString().padLeft(2, '0')} ج.م';
  }
}
