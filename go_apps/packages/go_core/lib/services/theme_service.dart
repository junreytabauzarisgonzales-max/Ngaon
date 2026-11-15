import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/go_theme.dart';
import 'storage_service.dart';

/// System / light / dark theme, persisted per device.
class ThemeService extends GetxService with WidgetsBindingObserver {
  ThemeService(this.storage);
  final StorageService storage;

  final mode = ThemeMode.system.obs;

  @override
  void onInit() {
    super.onInit();
    mode.value = ThemeMode.values.byName(storage.store.read<String>('theme_mode') ?? 'system');
    WidgetsBinding.instance.addObserver(this);
    _syncTokens();
  }

  bool get isDark => switch (mode.value) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
  };

  void _syncTokens() => GoColors.isDark = isDark;

  Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    await storage.store.write('theme_mode', m.name);
    _apply();
  }

  void _apply() {
    _syncTokens();
    Get.changeThemeMode(mode.value);
    // Widgets that read GoColors tokens directly must rebuild. Marking the
    // tree dirty is much cheaper than a reassemble (hot-reload path).
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }

  @override
  void didChangePlatformBrightness() {
    if (mode.value == ThemeMode.system) _apply();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
