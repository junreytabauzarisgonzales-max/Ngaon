import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../theme/go_theme.dart';

/// Shows a Go-styled bottom sheet.
///
/// `Get.bottomSheet` paints a transparent background by default, so every
/// sheet in the apps goes through here: solid themed surface, rounded top,
/// drag handle, optional title + close button, keyboard-aware padding, safe
/// area and a dimmed backdrop.
///
/// [tall] gives the sheet ~88 % of the screen and lets [child] manage its own
/// scrolling (use an `Expanded` list inside). Otherwise the sheet sizes to its
/// content and scrolls when it would exceed 90 % of the screen.
Future<T?> showGoSheet<T>({required Widget child, String? title, bool tall = false, bool dismissible = true}) {
  HapticFeedback.selectionClick();
  return Get.bottomSheet<T>(
    GoSheet(title: title, tall: tall, dismissible: dismissible, child: child),
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    enterBottomSheetDuration: const Duration(milliseconds: 260),
    exitBottomSheetDuration: const Duration(milliseconds: 200),
  );
}

class GoSheet extends StatelessWidget {
  const GoSheet({super.key, required this.child, this.title, this.tall = false, this.dismissible = true});
  final Widget child;
  final String? title;
  final bool tall;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final available = mq.size.height - mq.padding.top - keyboard;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: available * 0.92),
        height: tall ? available * 0.88 : null,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -4))],
        ),
        // Material (not a coloured box) so list tiles inside show ink ripples.
        child: Material(
          color: GoColors.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: GoColors.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                        if (dismissible)
                          IconButton.filledTonal(onPressed: Get.back, tooltip: 'common.close'.tr, icon: const Icon(Icons.close, size: 20)),
                      ],
                    ),
                  ),
                if (tall)
                  Expanded(child: child)
                else
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: child,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in [showGoOptions].
class GoOption<T> {
  const GoOption({required this.value, required this.label, this.icon, this.subtitle, this.danger = false});
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool danger;
}

/// A simple list of choices (photo source, navigation app, reasons…).
Future<T?> showGoOptions<T>({required List<GoOption<T>> options, String? title}) => showGoSheet<T>(
  title: title,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: GoColors.background,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              minTileHeight: 60,
              leading: o.icon == null
                  ? null
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (o.danger ? GoColors.danger : GoColors.primary).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(o.icon, color: o.danger ? GoColors.danger : GoColors.primary, size: 22),
                    ),
              title: Text(
                o.label,
                style: TextStyle(fontWeight: FontWeight.w600, color: o.danger ? GoColors.danger : null),
              ),
              subtitle: o.subtitle == null ? null : Text(o.subtitle!),
              trailing: Icon(Icons.chevron_right, color: GoColors.muted),
              onTap: () => Get.back(result: o.value),
            ),
          ),
        ),
    ],
  ),
);
