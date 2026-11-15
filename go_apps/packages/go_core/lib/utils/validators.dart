/// Philippine mobile number helpers.
class PhPhone {
  PhPhone._();

  static final _local = RegExp(r'^9\d{9}$');

  /// True when [input] is a local mobile number in the form `9XXXXXXXXX`.
  static bool isValidLocal(String input) => _local.hasMatch(input.replaceAll(RegExp(r'[\s-]'), ''));

  /// Normalizes `9XXXXXXXXX`, `09XXXXXXXXX`, `639XXXXXXXXX` or `+639XXXXXXXXX`
  /// to E.164 `+639XXXXXXXXX`. Returns null when invalid.
  static String? toE164(String input) {
    var digits = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.startsWith('+63')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('63') && digits.length == 12) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    return _local.hasMatch(digits) ? '+63$digits' : null;
  }

  /// `+639171234567` -> `+63 917 ••• 4567`.
  static String mask(String e164) {
    if (e164.length < 8) return e164;
    final local = e164.startsWith('+63') ? e164.substring(3) : e164;
    if (local.length != 10) return e164;
    return '+63 ${local.substring(0, 3)} ••• ${local.substring(6)}';
  }
}

bool isValidOtp(String code) => RegExp(r'^\d{6}$').hasMatch(code);

String? requiredText(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;
