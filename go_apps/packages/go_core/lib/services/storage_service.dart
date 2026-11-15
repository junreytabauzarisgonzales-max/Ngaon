import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// Sync key-value storage for settings and drafts.
abstract class KeyValueStore {
  T? read<T>(String key);
  Future<void> write(String key, Object? value);
  Future<void> remove(String key);
}

class GetStorageStore implements KeyValueStore {
  GetStorageStore(this._box);
  final GetStorage _box;

  static Future<GetStorageStore> open() async {
    await GetStorage.init('go');
    return GetStorageStore(GetStorage('go'));
  }

  @override
  T? read<T>(String key) => _box.read<T>(key);
  @override
  Future<void> write(String key, Object? value) => _box.write(key, value);
  @override
  Future<void> remove(String key) => _box.remove(key);
}

class MemoryStore implements KeyValueStore {
  final Map<String, Object?> data = {};
  @override
  T? read<T>(String key) => data[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// Settings + drafts that must survive app kills on weak devices.
class StorageService extends GetxService {
  StorageService(this.store);
  final KeyValueStore store;

  String get languageCode => store.read<String>('language') ?? 'en';
  Future<void> setLanguage(String code) => store.write('language', code);

  bool get onboardingDone => store.read<bool>('onboarding_done') ?? false;
  Future<void> setOnboardingDone() => store.write('onboarding_done', true);

  /// Drafts are stored as JSON strings under `draft.<key>`.
  Map<String, dynamic>? readDraft(String key) {
    final raw = store.read<String>('draft.$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDraft(String key, Map<String, dynamic> value) => store.write('draft.$key', jsonEncode(value));
  Future<void> clearDraft(String key) => store.remove('draft.$key');
}
