import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';

void main() {
  group('money', () {
    test('formats centavos', () {
      expect(formatCentavos(0), '₱0.00');
      expect(formatCentavos(5), '₱0.05');
      expect(formatCentavos(15000), '₱150.00');
      expect(formatCentavos(123450), '₱1,234.50');
      expect(formatCentavos(100000000), '₱1,000,000.00');
      expect(formatCentavos(-1300), '-₱13.00');
      expect(formatCentavos(500, showSign: true), '+₱5.00');
    });
    test('parses peso input without doubles', () {
      expect(parsePesosToCentavos('150'), 15000);
      expect(parsePesosToCentavos('1,234.5'), 123450);
      expect(parsePesosToCentavos('₱0.99'), 99);
      expect(parsePesosToCentavos('0.1'), 10);
      expect(parsePesosToCentavos('1.234'), isNull);
      expect(parsePesosToCentavos('abc'), isNull);
      expect(centavosToInput(15050), '150.50');
      expect(centavosToInput(15000), '150');
    });
    test('distance and duration', () {
      expect(formatDistance(850), '850 m');
      expect(formatDistance(1234), '1.2 km');
      expect(formatDistance(1250), '1.3 km');
      expect(formatDuration(420), '7 min');
      expect(formatDuration(3900), '1 h 5 min');
    });
  });

  group('PH phone', () {
    test('valid local', () {
      expect(PhPhone.isValidLocal('9171234567'), isTrue);
      expect(PhPhone.isValidLocal('917 123 4567'), isTrue);
      expect(PhPhone.isValidLocal('8171234567'), isFalse);
      expect(PhPhone.isValidLocal('917123456'), isFalse);
      expect(PhPhone.isValidLocal('09171234567'), isFalse);
    });
    test('E.164 normalization', () {
      expect(PhPhone.toE164('9171234567'), '+639171234567');
      expect(PhPhone.toE164('09171234567'), '+639171234567');
      expect(PhPhone.toE164('639171234567'), '+639171234567');
      expect(PhPhone.toE164('+63 917-123-4567'), '+639171234567');
      expect(PhPhone.toE164('+6328123456'), isNull);
      expect(PhPhone.toE164('12345'), isNull);
    });
    test('mask hides the middle digits', () {
      expect(PhPhone.mask('+639171234567'), '+63 917 ••• 4567');
    });
    test('otp', () {
      expect(isValidOtp('123456'), isTrue);
      expect(isValidOtp('12345'), isFalse);
      expect(isValidOtp('12a456'), isFalse);
    });
  });

  group('time', () {
    test('ISO UTC without millis, Manila display', () {
      final t = DateTime.utc(2026, 11, 14, 14, 5, 0, 123);
      expect(toIsoUtc(t), '2026-11-14T14:05:00Z');
      expect(formatManilaTime(t), '10:05 PM');
      expect(manilaDateString(DateTime.utc(2026, 11, 14, 17)), '2026-11-15');
    });
  });
}
