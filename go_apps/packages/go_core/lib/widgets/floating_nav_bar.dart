import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../theme/go_theme.dart';

class GoNavItem {
  const GoNavItem({required this.icon, required this.activeIcon, required this.labelKey, this.badge});
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;

  /// Optional reactive badge count (e.g. new orders, unread messages).
  final RxInt? badge;
}

/// Floating bottom bar made of circular buttons. The selected circle "pops
/// out": it grows, lifts above the bar with a soft glow, and its label
/// appears underneath. Transform-only animations keep it cheap on low-end
/// phones.
class GoFloatingNavBar extends StatelessWidget {
  const GoFloatingNavBar({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<GoNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const barHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: SizedBox(
        height: barHeight + 22, // room for the popped-out circle
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: GoColors.surface,
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(color: GoColors.line),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.5 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _CircleNavButton(item: items[i], selected: i == currentIndex, onTap: () => onTap(i)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleNavButton extends StatelessWidget {
  const _CircleNavButton({required this.item, required this.selected, required this.onTap});
  final GoNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 260);
    final primary = Theme.of(context).colorScheme.primary;
    final size = selected ? 58.0 : 46.0;
    return Semantics(
      selected: selected,
      button: true,
      label: item.labelKey.tr,
      child: GestureDetector(
        key: Key('nav.${item.labelKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedSlide(
              duration: duration,
              curve: Curves.easeOutBack,
              offset: selected ? const Offset(0, -0.12) : Offset.zero,
              child: AnimatedScale(
                // The "pop" overshoot lives on a transform only; layout values
                // below use a non-overshooting curve (no negative sizes/borders).
                duration: duration,
                curve: Curves.easeOutBack,
                scale: selected ? 1.0 : 0.94,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? primary : Colors.transparent,
                    border: Border.all(color: selected ? GoColors.surface : Colors.transparent, width: 4),
                    boxShadow: selected
                        ? [BoxShadow(color: primary.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))]
                        : const [],
                  ),
                  child: Center(
                    child: _badged(
                      Icon(
                        selected ? item.activeIcon : item.icon,
                        color: selected ? Colors.white : GoColors.muted,
                        size: selected ? 26 : 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedDefaultTextStyle(
              duration: duration,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? primary : GoColors.muted,
              ),
              child: Text(item.labelKey.tr, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _badged(Widget icon) {
    final badge = item.badge;
    if (badge == null) return icon;
    return Obx(() => Badge(isLabelVisible: badge.value > 0, label: Text('${badge.value}'), backgroundColor: GoColors.danger, child: icon));
  }
}

/// Tab shell: keeps each tab alive (IndexedStack) under the floating bar.
///
/// UX details: light haptic on tab change; tapping the current tab calls
/// [onReselect] (e.g. scroll to top); Android back on any other tab returns
/// to the first tab instead of closing the app.
class GoNavShell extends StatelessWidget {
  const GoNavShell({super.key, required this.items, required this.pages, required this.index, this.onReselect});

  final List<GoNavItem> items;
  final List<Widget> pages;
  final RxInt index;
  final ValueChanged<int>? onReselect;

  void _tap(int i) {
    if (i == index.value) {
      onReselect?.call(i);
      return;
    }
    HapticFeedback.selectionClick();
    index.value = i;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopScope(
        canPop: index.value == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) index.value = 0;
        },
        child: Scaffold(
          extendBody: true,
          body: IndexedStack(index: index.value, children: pages),
          bottomNavigationBar: GoFloatingNavBar(items: items, currentIndex: index.value, onTap: _tap),
        ),
      ),
    );
  }
}

/// Bottom padding that keeps scrollable content clear of the floating bar.
const goNavBarClearance = 120.0;
