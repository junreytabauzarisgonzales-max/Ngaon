import 'package:json_annotation/json_annotation.dart';

/// Which of the three Go apps is running.
@JsonEnum()
enum GoApp { customer, rider, merchant }

/// Runtime configuration. Values come from `--dart-define`.
class AppConfig {
  AppConfig({
    required this.app,
    String? apiBaseUrl,
    String? wsUrl,
    bool? useMockApi,
    String? googleMapsKey,
    this.appVersion = '1.0.0',
    this.enablePlatformPlugins = true,
    this.mockSpeed = 1.0,
    bool? devTools,
  }) : apiBaseUrl = apiBaseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080'),
       wsUrl = wsUrl ?? const String.fromEnvironment('WS_URL', defaultValue: 'ws://10.0.2.2:8080'),
       useMockApi = useMockApi ?? const bool.fromEnvironment('USE_MOCK_API', defaultValue: true),
       googleMapsKey = googleMapsKey ?? const String.fromEnvironment('GOOGLE_MAPS_KEY'),
       devTools = devTools ?? const bool.fromEnvironment('DEV_TOOLS');

  final GoApp app;

  /// Mutable so dev builds can switch servers at runtime (see [devTools]).
  String apiBaseUrl;
  String wsUrl;
  final bool useMockApi;
  final String googleMapsKey;
  final String appVersion;

  /// False in tests: push, local notifications, audio, wakelock, GPS and
  /// secure storage plugins are replaced by no-ops / in-memory versions.
  final bool enablePlatformPlugins;

  /// Multiplier for mock simulator delays (tests use small values).
  final double mockSpeed;

  /// `--dart-define=DEV_TOOLS=true`: shows the server-address setting on the
  /// login screen so testers can follow the backend's LAN IP without rebuilding.
  final bool devTools;

  /// Native Google Maps view is only shown when a key is configured.
  bool get mapsEnabled => googleMapsKey.isNotEmpty && enablePlatformPlugins;

  String get apiRoot => '$apiBaseUrl/api/v1';

  /// `http://host:port` -> `ws://host:port` (https -> wss).
  static String wsFor(String apiBase) => apiBase.replaceFirst(RegExp('^http'), 'ws');

  static late AppConfig current;
}
