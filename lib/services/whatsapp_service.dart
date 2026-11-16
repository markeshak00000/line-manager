import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
class WhatsAppService {
  static String normalizeEgypt(String raw) {
    var clean = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.startsWith('+')) clean = clean.substring(1);
    if (clean.startsWith('0020')) clean = clean.substring(4);
    if (clean.startsWith('20') && clean.length==12) return clean;
    if (clean.startsWith('0') && clean.length==11) return '20${clean.substring(1)}';
    return clean;
  }
  /// Real Android share: Share.shareXFiles uses Android Sharesheet. Never claims auto-send.
  static Future<void> shareReceipt(File image, {String? whatsappNumber, String caption=''}) async {
    if (!await image.exists()) throw ArgumentError('ملف الإيصال غير موجود');
    final text = caption.isEmpty ? 'إيصال الدفع — إدارة خطوط العملاء' : caption;
    // Use shareXFiles - Android will show WhatsApp in sheet. If user picked a number, also offer wa.me via openChat button in UI.
    await Share.shareXFiles([XFile(image.path, mimeType: 'image/png')], text: text);
  }
  static Future<void> openChat(String whatsappNumber, String text) async {
    final normalized = normalizeEgypt(whatsappNumber);
    final uri = Uri.parse('https://wa.me/$normalized?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); } else { throw StateError('تعذر فتح واتساب'); }
  }
}
