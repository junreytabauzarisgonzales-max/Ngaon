import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Brand design tokens.
class GoColors {
  GoColors._();
  static const primary = Color(0xFF0B8A5B); // Go green
  static const primaryDark = Color(0xFF066B45);
  static const accent = Color(0xFFFFB020); // amber
  static const danger = Color(0xFFD93A3A);
  static const warning = Color(0xFFF08C00);
  static const success = Color(0xFF1E9E5A);

  /// Fixed dark color for dark panels/backgrounds (same in both themes).
  static const night = Color(0xFF14201B);

  /// Set by [ThemeService] before rebuilding; neutral tokens follow it.
  static bool isDark = false;
  static GoPalette get palette => isDark ? GoPalette.dark : GoPalette.light;

  // Theme-aware neutrals (text, secondary text, cards, page, dividers).
  static Color get ink => palette.ink;
  static Color get muted => palette.muted;
  static Color get surface => palette.surface;
  static Color get background => palette.background;
  static Color get line => palette.line;

  static const ride = Color(0xFF0B8A5B);
  static const food = Color(0xFFE5533D);
  static const pabili = Color(0xFF3B6FE0);
  static const padala = Color(0xFFF08C00);
}

/// Neutral colors for one brightness.
class GoPalette {
  const GoPalette({
    required this.brightness,
    required this.ink,
    required this.muted,
    required this.surface,
    required this.background,
    required this.line,
  });
  final Brightness brightness;
  final Color ink;
  final Color muted;
  final Color surface;
  final Color background;
  final Color line;

  static const light = GoPalette(
    brightness: Brightness.light,
    ink: Color(0xFF14201B),
    muted: Color(0xFF66736D),
    surface: Color(0xFFFFFFFF),
    background: Color(0xFFF4F6F5),
    line: Color(0xFFE2E7E4),
  );

  static const dark = GoPalette(
    brightness: Brightness.dark,
    ink: Color(0xFFE8EEEB),
    muted: Color(0xFF9AA8A1),
    surface: Color(0xFF1B2622),
    background: Color(0xFF0F1714),
    line: Color(0xFF2A3732),
  );
}

class GoSpacing {
  GoSpacing._();
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0;
  static const radius = 16.0;
}

/// Status/navigation bar style for a palette: transparent status bar,
/// icons that contrast with the page.
SystemUiOverlayStyle _overlay(GoPalette p) => (p.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
    .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: p.background);

SystemUiOverlayStyle goOverlayStyle(Brightness b) => _overlay(b == Brightness.dark ? GoPalette.dark : GoPalette.light);

ThemeData goLightTheme() => goTheme(GoPalette.light);
ThemeData goDarkTheme() => goTheme(GoPalette.dark);

ThemeData goTheme(GoPalette p) {
  final dark = p.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: GoColors.primary,
    brightness: p.brightness,
    primary: dark ? const Color(0xFF2FBF86) : GoColors.primary,
    secondary: GoColors.accent,
    error: GoColors.danger,
    surface: p.surface,
    onSurface: p.ink,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: p.background, brightness: p.brightness);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(GoSpacing.radius));
  return base.copyWith(
    appBarTheme: AppBarTheme(
      systemOverlayStyle: _overlay(p),
      backgroundColor: p.background,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.ink),
    ),
    cardTheme: CardThemeData(color: p.surface, elevation: 0, margin: EdgeInsets.zero, shape: shape),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: shape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: p.line, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PopOutPageTransitionsBuilder(),
        TargetPlatform.iOS: PopOutPageTransitionsBuilder(),
        TargetPlatform.linux: PopOutPageTransitionsBuilder(),
      },
    ),
  );
}

/// "Pop-out" route animation: the new screen grows out of the old one
/// (scale 0.92 -> 1 + fade). Short and transform-only so it stays smooth on
/// low-end Android.
Widget _popOut(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curved), child: child),
  );
}

class PopOutPageTransitionsBuilder extends PageTransitionsBuilder {
  const PopOutPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _popOut(animation, child);
}

/// Same transition for GetX routes.
class PopOutTransition extends CustomTransition {
  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _popOut(animation, child);
}

Color serviceColor(String service) => switch (service) {
  'food' => GoColors.food,
  'pabili' => GoColors.pabili,
  'padala' => GoColors.padala,
  _ => GoColors.ride,
};

IconData serviceIcon(String service) => switch (service) {
  'food' => Icons.restaurant,
  'pabili' => Icons.shopping_basket,
  'padala' => Icons.inventory_2,
  _ => Icons.two_wheeler,
};
