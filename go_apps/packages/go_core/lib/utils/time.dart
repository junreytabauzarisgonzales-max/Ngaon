import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

/// Asia/Manila is UTC+8 with no daylight saving time.
const manilaOffset = Duration(hours: 8);

/// Returns a DateTime whose wall-clock fields are Manila local time.
/// (The returned value is marked UTC so the framework never re-applies the
/// device zone; only use it for display.)
DateTime toManila(DateTime t) => t.toUtc().add(manilaOffset);

DateTime manilaNow() => toManila(DateTime.now());

String formatManilaTime(DateTime t) => DateFormat('h:mm a').format(toManila(t));
String formatManilaDate(DateTime t) => DateFormat('MMM d, y').format(toManila(t));
String formatManilaDateTime(DateTime t) => DateFormat('MMM d, h:mm a').format(toManila(t));

/// `YYYY-MM-DD` for the given Manila calendar day.
String manilaDateString(DateTime t) => DateFormat('yyyy-MM-dd').format(toManila(t));

/// ISO 8601 UTC without milliseconds: `2026-11-14T14:05:00Z`.
String toIsoUtc(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

class UtcDateTimeConverter implements JsonConverter<DateTime, String> {
  const UtcDateTimeConverter();
  @override
  DateTime fromJson(String json) => DateTime.parse(json).toUtc();
  @override
  String toJson(DateTime object) => toIsoUtc(object);
}

class NullableUtcDateTimeConverter implements JsonConverter<DateTime?, String?> {
  const NullableUtcDateTimeConverter();
  @override
  DateTime? fromJson(String? json) => json == null ? null : DateTime.parse(json).toUtc();
  @override
  String? toJson(DateTime? object) => object == null ? null : toIsoUtc(object);
}
