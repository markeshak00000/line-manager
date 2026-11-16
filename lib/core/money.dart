/// Money is stored as integer piasters. 1 EGP = 100 piasters.
class Money {
  static int fromEGPInt(int egp) => egp * 100;

  /// Parses Arabic or western digits without floating point arithmetic.
  /// Accepts values such as 250, 250.5, 250.50, or ٢٥٠٫٥٠.
  static int? parseEGP(String input) {
    var value = input.trim();
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var index = 0; index < arabicDigits.length; index++) {
      value = value.replaceAll(arabicDigits[index], '$index');
    }
    value = value.replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final pounds = int.tryParse(parts.first);
    if (pounds == null) return null;
    final piasters = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return pounds * 100 + piasters;
  }

  static String format(int piasters) {
    final negative = piasters < 0;
    final absolute = piasters.abs();
    final pounds = absolute ~/ 100;
    final fraction = absolute % 100;
    final value = fraction == 0
        ? '$pounds'
        : '$pounds.${fraction.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}$value ج.م';
  }

  static String formatPlain(int piasters) => format(piasters);
}
