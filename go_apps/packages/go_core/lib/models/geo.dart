import 'dart:math' as math;

import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';

part 'geo.g.dart';

@JsonSerializable()
class LatLng {
  const LatLng({required this.lat, required this.lng});
  final double lat;
  final double lng;

  /// Bongao, Tawi-Tawi town center.
  static const bongao = LatLng(lat: 5.0294, lng: 119.7730);

  /// Great-circle distance in meters.
  int distanceTo(LatLng o) {
    const r = 6371000.0;
    final dLat = _rad(o.lat - lat), dLng = _rad(o.lng - lng);
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(lat)) * math.cos(_rad(o.lat)) * math.pow(math.sin(dLng / 2), 2);
    return (2 * r * math.asin(math.sqrt(a))).round();
  }

  static double _rad(double d) => d * math.pi / 180;

  LatLng lerp(LatLng to, double t) => LatLng(lat: lat + (to.lat - lat) * t, lng: lng + (to.lng - lng) * t);

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lng == lng;
  @override
  int get hashCode => Object.hash(lat, lng);
  @override
  String toString() => '($lat, $lng)';

  factory LatLng.fromJson(Map<String, dynamic> json) => _$LatLngFromJson(json);
  Map<String, dynamic> toJson() => _$LatLngToJson(this);
}

@JsonSerializable()
class SavedPlace {
  SavedPlace({required this.id, required this.label, required this.address, required this.location});
  final String id;
  final String label;
  final String address;
  final LatLng location;

  factory SavedPlace.fromJson(Map<String, dynamic> json) => _$SavedPlaceFromJson(json);
  Map<String, dynamic> toJson() => _$SavedPlaceToJson(this);
}

@JsonSerializable()
class Stop {
  Stop({required this.address, required this.location, this.contactName, this.contactPhone, this.notes});
  final String address;
  final LatLng location;
  final String? contactName;
  final String? contactPhone;
  final String? notes;

  Stop copyWith({String? notes, String? contactName, String? contactPhone}) => Stop(
    address: address,
    location: location,
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
    notes: notes ?? this.notes,
  );

  factory Stop.fromJson(Map<String, dynamic> json) => _$StopFromJson(json);
  Map<String, dynamic> toJson() => _$StopToJson(this);
}

@JsonSerializable()
class GeoSearchResult {
  GeoSearchResult({required this.name, required this.address, required this.location});
  final String name;
  final String address;
  final LatLng location;

  factory GeoSearchResult.fromJson(Map<String, dynamic> json) => _$GeoSearchResultFromJson(json);
  Map<String, dynamic> toJson() => _$GeoSearchResultToJson(this);
}

@JsonSerializable()
class ReverseGeocodeResult {
  ReverseGeocodeResult({required this.address});
  final String address;

  factory ReverseGeocodeResult.fromJson(Map<String, dynamic> json) => _$ReverseGeocodeResultFromJson(json);
  Map<String, dynamic> toJson() => _$ReverseGeocodeResultToJson(this);
}

@JsonSerializable()
class ServiceZone {
  ServiceZone({required this.id, required this.name, required this.polygon});
  final String id;
  final String name;
  final List<LatLng> polygon;

  /// Ray-casting point-in-polygon test.
  bool contains(LatLng p) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.lat > p.lat) != (b.lat > p.lat) && p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) {
        inside = !inside;
      }
    }
    return inside;
  }

  factory ServiceZone.fromJson(Map<String, dynamic> json) => _$ServiceZoneFromJson(json);
  Map<String, dynamic> toJson() => _$ServiceZoneToJson(this);
}

@JsonSerializable()
class ServiceArea {
  ServiceArea({required this.zones});
  final List<ServiceZone> zones;

  bool contains(LatLng p) => zones.any((z) => z.contains(p));

  factory ServiceArea.fromJson(Map<String, dynamic> json) => _$ServiceAreaFromJson(json);
  Map<String, dynamic> toJson() => _$ServiceAreaToJson(this);
}

/// Body of `rider.location` (WS) and `POST /rider/location`.
@JsonSerializable()
@UtcDateTimeConverter()
class LocationPing {
  LocationPing({required this.location, this.heading, this.speedKph, required this.recordedAt});
  final LatLng location;
  final double? heading;
  final double? speedKph;
  final DateTime recordedAt;

  factory LocationPing.fromJson(Map<String, dynamic> json) => _$LocationPingFromJson(json);
  Map<String, dynamic> toJson() => _$LocationPingToJson(this);
}
