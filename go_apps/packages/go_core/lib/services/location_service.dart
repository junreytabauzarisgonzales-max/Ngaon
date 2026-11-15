import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../models/geo.dart';

class GoPosition {
  const GoPosition(this.location, {this.heading, this.speedKph, required this.at});
  final LatLng location;
  final double? heading;
  final double? speedKph;
  final DateTime at;
}

enum LocationPermissionState { granted, denied, deniedForever, serviceOff }

class LocationService extends GetxService {
  final last = Rxn<GoPosition>();
  StreamSubscription<Position>? _sub;

  bool get _real => AppConfig.current.enablePlatformPlugins;

  Future<LocationPermissionState> check() async {
    if (!_real) return LocationPermissionState.granted;
    if (!await Geolocator.isLocationServiceEnabled()) return LocationPermissionState.serviceOff;
    return _map(await Geolocator.checkPermission());
  }

  Future<LocationPermissionState> request() async {
    if (!_real) return LocationPermissionState.granted;
    if (!await Geolocator.isLocationServiceEnabled()) return LocationPermissionState.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return _map(p);
  }

  LocationPermissionState _map(LocationPermission p) => switch (p) {
    LocationPermission.always || LocationPermission.whileInUse => LocationPermissionState.granted,
    LocationPermission.deniedForever => LocationPermissionState.deniedForever,
    _ => LocationPermissionState.denied,
  };

  Future<void> openSettings() => Geolocator.openAppSettings();

  /// Current location, falling back to the last fix or Bongao center.
  Future<LatLng> current() async {
    if (!_real) return last.value?.location ?? LatLng.bongao;
    try {
      if (await check() != LocationPermissionState.granted) return last.value?.location ?? LatLng.bongao;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      _set(p);
      return last.value!.location;
    } catch (_) {
      final lk = await Geolocator.getLastKnownPosition();
      if (lk != null) _set(lk);
      return last.value?.location ?? LatLng.bongao;
    }
  }

  void _set(Position p) {
    last.value = GoPosition(
      LatLng(lat: p.latitude, lng: p.longitude),
      heading: p.heading,
      speedKph: p.speed < 0 ? null : p.speed * 3.6,
      at: p.timestamp.toUtc(),
    );
  }

  /// Continuous tracking. On Android with [foregroundTitle] this runs as a
  /// foreground service with a persistent notification (rider while online).
  Future<void> startTracking({String? foregroundTitle, String? foregroundText}) async {
    if (!_real || _sub != null) return;
    final settings = foregroundTitle == null
        ? const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
        : AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: foregroundTitle,
              notificationText: foregroundText ?? '',
              enableWakeLock: true,
              setOngoing: true,
            ),
          );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(_set, onError: (_) {});
  }

  Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// For mock mode / tests: inject a position.
  void injectPosition(LatLng p, {double? speedKph}) => last.value = GoPosition(p, speedKph: speedKph, at: DateTime.now().toUtc());
}
