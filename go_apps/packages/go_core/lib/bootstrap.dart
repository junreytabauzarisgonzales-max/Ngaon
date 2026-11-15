import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'config/app_config.dart';
import 'network/api_client.dart';
import 'network/session_store.dart';
import 'network/ws_client.dart';
import 'repositories/http/http_repositories.dart';
import 'repositories/mock/mock_backend.dart';
import 'repositories/mock/mock_repositories.dart';
import 'repositories/repositories.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/network_status.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'services/upload_service.dart';
import 'theme/go_theme.dart';
import 'translations/core_translations.dart';
import 'widgets/chat.dart';
import 'widgets/common.dart';
import 'widgets/location_picker.dart';

/// Routes provided by go_core.
class CoreRoutes {
  CoreRoutes._();
  static const chat = '/chat';
  static const locationPicker = '/location-picker';

  static List<GetPage<dynamic>> pages() => [
    GetPage(name: chat, page: () => const ChatView(), binding: ChatBinding(), middlewares: [AuthMiddleware()]),
    GetPage(name: locationPicker, page: () => const LocationPickerView(), binding: LocationPickerBinding()),
  ];
}

/// Redirects to login when there is no session.
class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) => Get.find<AuthService>().isLoggedIn ? null : const RouteSettings(name: '/login');
}

/// Registers repositories: HTTP or mock depending on `USE_MOCK_API`.
class GoRepositoryBinding extends Bindings {
  GoRepositoryBinding({this.mock});
  final MockBackend? mock;

  @override
  void dependencies() {
    final m = mock;
    if (m != null) {
      Get.put<AuthRepository>(MockAuthRepository(m), permanent: true);
      Get.put<GeoRepository>(MockGeoRepository(m), permanent: true);
      Get.put<MerchantsRepository>(MockMerchantsRepository(m), permanent: true);
      Get.put<JobsRepository>(MockJobsRepository(m), permanent: true);
      Get.put<ChatRepository>(MockChatRepository(m), permanent: true);
      Get.put<UploadsRepository>(MockUploadsRepository(m), permanent: true);
      Get.put<RiderRepository>(MockRiderRepository(m), permanent: true);
      Get.put<MerchantAdminRepository>(MockMerchantAdminRepository(m), permanent: true);
      Get.put<GoWsClient>(MockWsClient(m), permanent: true);
      return;
    }
    final api = Get.find<ApiClient>();
    Get.put<AuthRepository>(HttpAuthRepository(api), permanent: true);
    Get.put<GeoRepository>(HttpGeoRepository(api), permanent: true);
    Get.put<MerchantsRepository>(HttpMerchantsRepository(api), permanent: true);
    Get.put<JobsRepository>(HttpJobsRepository(api), permanent: true);
    Get.put<ChatRepository>(HttpChatRepository(api), permanent: true);
    Get.put<UploadsRepository>(HttpUploadsRepository(api), permanent: true);
    Get.put<RiderRepository>(HttpRiderRepository(api), permanent: true);
    Get.put<MerchantAdminRepository>(HttpMerchantAdminRepository(api), permanent: true);
    final session = Get.find<SessionStore>();
    Get.put<GoWsClient>(
      RealWsClient(wsUrl: AppConfig.current.wsUrl, accessToken: () => session.accessToken, refreshToken: api.refreshTokens),
      permanent: true,
    );
  }
}

/// Initializes config, storage, session, network, services and repositories.
/// Tests pass in-memory stores and a [MockBackend].
Future<void> initGoCore(AppConfig config, {KeyValueStore? store, SecureKeyValue? secure, MockBackend? mockBackend}) async {
  AppConfig.current = config;
  final storage = Get.put(StorageService(store ?? await GetStorageStore.open()), permanent: true);
  Get.put(ThemeService(storage), permanent: true);
  final session = Get.put(SessionStore(secure ?? PlatformSecureKeyValue()), permanent: true);
  final auth = Get.put(AuthService(session: session, storage: storage), permanent: true);
  await auth.restore();
  final net = Get.put(NetworkStatus(), permanent: true);

  Get.put(
    ApiClient(
      config: config,
      session: session,
      languageCode: () => storage.languageCode,
      onSessionExpired: () => auth.logout(remote: false),
      onNetworkStatus: net.report,
    ),
    permanent: true,
  );

  MockBackend? mock = mockBackend;
  if (config.useMockApi && mock == null) {
    mock = MockBackend(app: config.app, speed: config.mockSpeed);
    await mock.init();
  }
  if (mock != null) {
    Get.put(mock, permanent: true);
    auth.onLogout.add(() async => mock!.stopSimulations());
    if (auth.isLoggedIn) mock.restoreSession();
  }
  GoRepositoryBinding(mock: config.useMockApi ? mock : null).dependencies();

  final ws = Get.find<GoWsClient>();
  ws.state.listen((s) {
    if (s == WsState.connected) net.report(true);
  });

  Get.put(UploadService(), permanent: true);
  Get.put(LocationService(), permanent: true);
  await Get.putAsync(() => NotificationService().init(), permanent: true);
  final push = await Get.putAsync(() => PushService().init(), permanent: true);

  auth.onLogin.add(() async {
    await ws.connect();
    unawaited(push.register());
  });
}

/// Builds the GetMaterialApp shared by all apps.
Widget buildGoApp({
  required String title,
  required String initialRoute,
  required List<GetPage<dynamic>> pages,
  required Map<String, Map<String, String>> translations,
  Bindings? initialBinding,
}) {
  final lang = Get.find<StorageService>().languageCode;
  return GetMaterialApp(
    title: title,
    debugShowCheckedModeBanner: false,
    theme: goLightTheme(),
    darkTheme: goDarkTheme(),
    themeMode: Get.find<ThemeService>().mode.value,
    translations: GoTranslations(translations),
    locale: lang == 'fil' ? const Locale('fil', 'PH') : const Locale('en', 'US'),
    fallbackLocale: const Locale('en', 'US'),
    initialRoute: initialRoute,
    initialBinding: initialBinding,
    getPages: [...pages, ...CoreRoutes.pages()],
    customTransition: PopOutTransition(),
    transitionDuration: const Duration(milliseconds: 240),
    // Status bar icons follow the theme even on screens without an AppBar.
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: goOverlayStyle(Theme.of(context).brightness),
      child: Column(children: [const OfflineBanner(), Expanded(child: child ?? const SizedBox.shrink())]),
    ),
  );
}

/// Standard entry point used by each app's `main()`.
Future<void> bootstrapGoApp({
  required AppConfig config,
  required String title,
  required String initialRoute,
  required List<GetPage<dynamic>> pages,
  required Map<String, Map<String, String>> translations,
  Bindings? initialBinding,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initGoCore(config);
  runApp(buildGoApp(title: title, initialRoute: initialRoute, pages: pages, translations: translations, initialBinding: initialBinding));
}

/// Changes app language (persisted, sent as Accept-Language, synced to PATCH /me).
Future<void> setGoLanguage(String code) async {
  await Get.find<StorageService>().setLanguage(code);
  await Get.updateLocale(code == 'fil' ? const Locale('fil', 'PH') : const Locale('en', 'US'));
}
