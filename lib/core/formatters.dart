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
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }
}
