import 'package:get/get.dart';

/// Tracks reachability from request outcomes and the WebSocket state.
/// (connectivity_plus conflicts with geolocator's dbus pin, and real
/// reachability is what matters on flaky island networks anyway.)
class NetworkStatus extends GetxService {
  final online = true.obs;
  void report(bool reachable) {
    if (online.value != reachable) online.value = reachable;
  }
}
