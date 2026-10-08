/// Formateo para la UI en español (México). Sin dependencias de `intl`.
abstract final class Fmt {
  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  /// 850 → "850 m" · 1234 → "1.2 km"
  static String distance(num meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// 45 → "45 s" · 130 → "2 min" · 3900 → "1 h 5 min"
  static String duration(num seconds) {
    final s = seconds.round();
    if (s < 60) return '$s s';
    final m = s ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h h' : '$h h $rest min';
  }

  /// "hace 3 min", "hace 2 h", "hace 1 d"
  static String ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  /// "18:17" en hora local.
  static String time(DateTime t) {
    final l = t.toLocal();
    return '${_2(l.hour)}:${_2(l.minute)}';
  }

  /// "7 oct 2026"
  static String date(DateTime t) {
    final l = t.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  /// "7 oct · 18:17"
  static String dateTime(DateTime t) {
    final l = t.toLocal();
    return '${l.day} ${_months[l.month - 1]} · ${time(t)}';
  }

  /// 0.234 → "23 %"
  static String percent(double ratio) => '${(ratio * 100).round()} %';

  /// "7771234567" → "777 123 4567"
  static String phone(String p) =>
      p.length == 10 ? '${p.substring(0, 3)} ${p.substring(3, 6)} ${p.substring(6)}' : p;

  static String _2(int n) => n.toString().padLeft(2, '0');
}
