import 'dart:convert';

import 'package:get/get.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../models/user.dart';
import '../network/session_store.dart';
import '../network/ws_client.dart';
import '../repositories/repositories.dart';
import 'storage_service.dart';

/// Owns the session: tokens, current user, logout.
class AuthService extends GetxService {
  AuthService({required this.session, required this.storage});

  final SessionStore session;
  final StorageService storage;

  final user = Rxn<User>();

  /// Called after login / session restore (push registration, mock simulation).
  final List<Future<void> Function()> onLogin = [];

  /// Called on logout (stop tracking, alarms, etc.).
  final List<Future<void> Function()> onLogout = [];

  AuthRepository get _repo => Get.find<AuthRepository>();

  bool get isLoggedIn => session.hasSession;

  Future<void> restore() async {
    await session.load();
    final cached = storage.store.read<String>('user');
    if (cached != null) {
      try {
        user.value = User.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> completeLogin(AuthResult result) async {
    await session.save(result.accessToken, result.refreshToken);
    setUser(result.user);
    await _runHooks(onLogin);
  }

  void setUser(User u) {
    user.value = u;
    storage.store.write('user', jsonEncode(u.toJson()));
  }

  Future<User?> refreshMe() async {
    try {
      final u = await _repo.me();
      setUser(u);
      return u;
    } catch (_) {
      return user.value;
    }
  }

  Future<void> afterRestore() => _runHooks(onLogin);

  Future<void> _runHooks(List<Future<void> Function()> hooks) async {
    for (final h in hooks) {
      try {
        await h();
      } catch (_) {}
    }
  }

  /// Logs out locally (and remotely when [remote]). Navigates to login.
  Future<void> logout({bool remote = true}) async {
    final rt = session.refreshToken;
    if (remote && rt != null) {
      try {
        await _repo.logout(rt);
      } catch (_) {}
    }
    await _runHooks(onLogout);
    await session.clear();
    await storage.store.remove('user');
    user.value = null;
    if (Get.isRegistered<GoWsClient>()) await Get.find<GoWsClient>().disconnect();
    Get.offAllNamed('/login');
  }

  String get appName => AppConfig.current.app.name;

  AppLanguage get language => storage.languageCode == 'fil' ? AppLanguage.fil : AppLanguage.en;
}
