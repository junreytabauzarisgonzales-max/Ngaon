import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../network/api_exception.dart';
import '../theme/go_theme.dart';

/// Central translated error messages per error code (Section 6).
class GoErrors {
  GoErrors._();

  static String message(Object error) {
    if (error is ApiException) {
      if (error.code == ErrorCodes.rateLimited && (error.retryAfterSeconds ?? 0) > 0) {
        return 'error.rate_limited_wait'.trParams({'s': '${error.retryAfterSeconds}'});
      }
      final key = 'error.${error.code}';
      final t = key.tr;
      if (t != key) return t;
      return error.message.isNotEmpty ? error.message : 'error.unknown'.tr;
    }
    return 'error.unknown'.tr;
  }

  /// Keep snackbars clear of the floating tab bar on tab screens.
  static EdgeInsets get _margin => EdgeInsets.fromLTRB(12, 12, 12, Get.currentRoute == '/home' ? 112 : 12);

  static String? code(Object error) => error is ApiException ? error.code : null;

  /// Shows a snackbar. Session errors are handled by the API client.
  static void show(Object error) {
    if (Get.context == null) return;
    Get.closeCurrentSnackbar();
    Get.showSnackbar(
      GetSnackBar(
        message: message(error),
        backgroundColor: GoColors.night,
        icon: const Icon(Icons.error_outline, color: GoColors.accent),
        duration: const Duration(seconds: 3),
        margin: _margin,
        borderRadius: 12,
      ),
    );
  }

  static void toast(String text) {
    if (Get.context == null) return;
    Get.closeCurrentSnackbar();
    Get.showSnackbar(
      GetSnackBar(message: text, duration: const Duration(seconds: 2), margin: _margin, borderRadius: 12, backgroundColor: GoColors.night),
    );
  }

  /// Runs [action], showing errors. Returns null on failure.
  static Future<T?> guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      show(e);
      return null;
    }
  }
}
