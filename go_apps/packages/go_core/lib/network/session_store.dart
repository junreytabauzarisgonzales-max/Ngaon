import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal async key-value API for secrets (real: Keystore-backed, tests: memory).
abstract class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class PlatformSecureKeyValue implements SecureKeyValue {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String? value) => value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

class MemorySecureKeyValue implements SecureKeyValue {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? data.remove(key) : data[key] = value;
}

/// Holds access/refresh tokens in memory, persisted in secure storage.
class SessionStore {
  SessionStore(this._secure);
  final SecureKeyValue _secure;

  String? accessToken;
  String? refreshToken;

  bool get hasSession => refreshToken != null;

  Future<void> load() async {
    accessToken = await _secure.read('access_token');
    refreshToken = await _secure.read('refresh_token');
  }

  Future<void> save(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    await _secure.write('access_token', access);
    await _secure.write('refresh_token', refresh);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    await _secure.write('access_token', null);
    await _secure.write('refresh_token', null);
  }
}
