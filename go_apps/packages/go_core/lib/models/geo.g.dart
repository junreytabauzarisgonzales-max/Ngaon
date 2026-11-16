// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LatLng _$LatLngFromJson(Map<String, dynamic> json) => LatLng(lat: (json['lat'] as num).toDouble(), lng: (json['lng'] as num).toDouble());

Map<String, dynamic> _$LatLngToJson(LatLng instance) => <String, dynamic>{'lat': instance.lat, 'lng': instance.lng};

SavedPlace _$SavedPlaceFromJson(Map<String, dynamic> json) => SavedPlace(
  id: json['id'] as String,
  label: json['label'] as String,
  address: json['address'] as String,
  location: LatLng.fromJson(json['location'] as Map<String, dynamic>),
);

Map<String, dynamic> _$SavedPlaceToJson(SavedPlace instance) => <String, dynamic>{
  'id': instance.id,
  'label': instance.label,
  'address': instance.address,
  'location': instance.location.toJson(),
};

Stop _$StopFromJson(Map<String, dynamic> json) => Stop(
  address: json['address'] as String,
  location: LatLng.fromJson(json['location'] as Map<String, dynamic>),
  contactName: json['contact_name'] as String?,
  contactPhone: json['contact_phone'] as String?,
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$StopToJson(Stop instance) => <String, dynamic>{
  'address': instance.address,
  'location': instance.location.toJson(),
  'contact_name': ?instance.contactName,
  'contact_phone': ?instance.contactPhone,
  'notes': ?instance.notes,
};

GeoSearchResult _$GeoSearchResultFromJson(Map<String, dynamic> json) => GeoSearchResult(
  name: json['name'] as String,
  address: json['address'] as String,
  location: LatLng.fromJson(json['location'] as Map<String, dynamic>),
);

Map<String, dynamic> _$GeoSearchResultToJson(GeoSearchResult instance) => <String, dynamic>{
  'name': instance.name,
  'address': instance.address,
  'location': instance.location.toJson(),
};

ReverseGeocodeResult _$ReverseGeocodeResultFromJson(Map<String, dynamic> json) => ReverseGeocodeResult(address: json['address'] as String);

Map<String, dynamic> _$ReverseGeocodeResultToJson(ReverseGeocodeResult instance) => <String, dynamic>{'address': instance.address};

ServiceZone _$ServiceZoneFromJson(Map<String, dynamic> json) => ServiceZone(
  id: json['id'] as String,
  name: json['name'] as String,
  polygon: (json['polygon'] as List<dynamic>).map((e) => LatLng.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$ServiceZoneToJson(ServiceZone instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'polygon': instance.polygon.map((e) => e.toJson()).toList(),
};

ServiceArea _$ServiceAreaFromJson(Map<String, dynamic> json) =>
    ServiceArea(zones: (json['zones'] as List<dynamic>).map((e) => ServiceZone.fromJson(e as Map<String, dynamic>)).toList());

Map<String, dynamic> _$ServiceAreaToJson(ServiceArea instance) => <String, dynamic>{
  'zones': instance.zones.map((e) => e.toJson()).toList(),
};

LocationPing _$LocationPingFromJson(Map<String, dynamic> json) => LocationPing(
  location: LatLng.fromJson(json['location'] as Map<String, dynamic>),
  heading: (json['heading'] as num?)?.toDouble(),
  speedKph: (json['speed_kph'] as num?)?.toDouble(),
  recordedAt: const UtcDateTimeConverter().fromJson(json['recorded_at'] as String),
);

Map<String, dynamic> _$LocationPingToJson(LocationPing instance) => <String, dynamic>{
  'location': instance.location.toJson(),
  'heading': ?instance.heading,
  'speed_kph': ?instance.speedKph,
  'recorded_at': const UtcDateTimeConverter().toJson(instance.recordedAt),
};
