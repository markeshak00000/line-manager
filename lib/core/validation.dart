class Validation {
  static String? requiredName(String? v) { if (v==null||v.trim().isEmpty) return 'الاسم مطلوب'; if (v.trim().length<2) return 'الاسم قصير جداً'; return null; }
  static String? lineNumber(String? v) {
    if (v==null||v.trim().isEmpty) return 'رقم الخط مطلوب';
    final t=v.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^01[0-9]{9}$').hasMatch(t)) return 'رقم الخط يجب أن يبدأ بـ 01 ويتكون من 11 رقماً';
    return null;
  }
  static String? phone(String? v) { if (v==null||v.trim().isEmpty) return null; final t=v.trim().replaceAll(RegExp(r'[\s-]'), ''); if (!RegExp(r'^01[0-9]{9}$').hasMatch(t) && !RegExp(r'^\+20[0-9]{10}$').hasMatch(t)) return 'رقم غير صحيح'; return null; }
  static String? amount(int piasters) { if (piasters<=0) return 'المبلغ يجب أن يكون أكبر من صفر'; if (piasters>100000000) return 'المبلغ غير منطقي'; return null; }
  static String normalizeLine(String v) => v.trim().replaceAll(RegExp(r'[\s-]'), '');
  static String normalizePhone(String v) => v.trim().replaceAll(RegExp(r'[\s-]'), '');
}
