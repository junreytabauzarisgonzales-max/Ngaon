import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/theme_service.dart';

/// System / Light / Dark switcher (used on every app's profile screen).
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Get.find<ThemeService>();
    return Obx(
      () => SegmentedButton<ThemeMode>(
        key: const Key('theme.selector'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto), label: Text('theme.system'.tr)),
          ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text('theme.light'.tr)),
          ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text('theme.dark'.tr)),
        ],
        selected: {t.mode.value},
        onSelectionChanged: (s) => t.setMode(s.first),
      ),
    );
  }
}
