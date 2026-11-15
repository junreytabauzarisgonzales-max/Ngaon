/// Money is always integer centavos. Never use doubles for money.
String formatCentavos(int centavos, {bool showSign = false}) {
  final negative = centavos < 0;
  final abs = centavos.abs();
  final pesos = abs ~/ 100;
  final cents = abs % 100;
  final digits = pesos.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final sign = negative ? '-' : (showSign && centavos > 0 ? '+' : '');
  return '$sign₱$buf.${cents.toString().padLeft(2, '0')}';
}

/// Parses user input like "150", "1,234.5" or "₱99.99" into centavos.
/// Returns null for invalid input or more than 2 decimal places.
int? parsePesosToCentavos(String input) {
  final cleaned = input.replaceAll(RegExp(r'[₱,\s]'), '');
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{0,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final pesos = int.parse(match.group(1)!);
  final frac = (match.group(2) ?? '').padRight(2, '0');
  return pesos * 100 + int.parse(frac);
}

/// Centavos to an editable string without currency symbol, e.g. 15050 -> "150.50".
String centavosToInput(int centavos) {
  final pesos = centavos ~/ 100;
  final cents = centavos % 100;
  return cents == 0 ? '$pesos' : '$pesos.${cents.toString().padLeft(2, '0')}';
}

/// 850 -> "850 m", 1234 -> "1.2 km".
String formatDistance(int meters) {
  if (meters < 1000) return '$meters m';
  final tenths = (meters + 50) ~/ 100; // round to 0.1 km
  return '${tenths ~/ 10}.${tenths % 10} km';
}

/// Seconds to "5 min" / "1 h 5 min".
String formatDuration(int seconds) {
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}
