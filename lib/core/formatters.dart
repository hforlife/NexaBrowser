/// Mise en forme lisible (français).
library;

class Formatters {
  Formatters._();

  /// 845 o · 12 Ko · 3,4 Mo · 1,2 Go
  static String bytes(int? size) {
    if (size == null || size < 0) return '—';
    const List<String> units = ['o', 'Ko', 'Mo', 'Go'];
    double value = size.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final String number = unit == 0 || value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$number ${units[unit]}';
  }

  /// « à l'instant », « il y a 5 min », « hier », « 12/10/2026 »
  static String relativeDate(DateTime date) {
    final Duration diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    return Formatters.date(date);
  }

  /// « 12/10/2026 »
  static String date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  /// 1 234 567 → « 1 234 567 » (espace insécable fine entre les milliers).
  static String count(int value) {
    final String digits = value.abs().toString();
    final StringBuffer buffer = StringBuffer(value < 0 ? '-' : '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
