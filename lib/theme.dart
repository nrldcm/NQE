// NQE visual identity — a clean monochrome system (matching the NQE / Willong
// "leaf" mark) with green/red reserved for gains/losses. Full light + dark
// support; the chosen mode is persisted via ThemeController.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NqeColors {
  // Semantic P&L colours — identical in both themes.
  static const gain = Color(0xFF17B978);
  static const loss = Color(0xFFE5484D);
  static Color pnl(double v) => v >= 0 ? gain : loss;
}

/// Theme-aware palette resolved from the current [ThemeData]. Widgets read it
/// via `context.nqe`, so the same widget renders correctly in light and dark.
class NqePalette {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color textHi;
  final Color textLo;
  final bool isDark;

  const NqePalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.textHi,
    required this.textLo,
    required this.isDark,
  });

  static NqePalette of(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return NqePalette(
      bg: t.scaffoldBackgroundColor,
      surface: cs.surfaceContainer,
      surface2: cs.surfaceContainerHighest,
      line: cs.outlineVariant,
      textHi: cs.onSurface,
      textLo: cs.onSurfaceVariant,
      isDark: t.brightness == Brightness.dark,
    );
  }
}

extension NqeContext on BuildContext {
  NqePalette get nqe => NqePalette.of(this);
}

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFF5F5F5),
  onPrimary: Color(0xFF0A0A0A),
  secondary: Color(0xFF9A9A9A),
  onSecondary: Color(0xFF0A0A0A),
  error: NqeColors.loss,
  onError: Colors.white,
  surface: Color(0xFF0A0A0A),
  onSurface: Color(0xFFF5F5F5),
  onSurfaceVariant: Color(0xFF9A9A9A),
  surfaceContainerLowest: Color(0xFF060606),
  surfaceContainerLow: Color(0xFF111111),
  surfaceContainer: Color(0xFF141414),
  surfaceContainerHigh: Color(0xFF1B1B1B),
  surfaceContainerHighest: Color(0xFF232323),
  outline: Color(0xFF3A3A3A),
  outlineVariant: Color(0xFF2A2A2A),
);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0A0A0A),
  onPrimary: Color(0xFFFFFFFF),
  secondary: Color(0xFF6B6B6B),
  onSecondary: Color(0xFFFFFFFF),
  error: NqeColors.loss,
  onError: Colors.white,
  surface: Color(0xFFF7F7F5),
  onSurface: Color(0xFF14140F),
  onSurfaceVariant: Color(0xFF6B6B6B),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceContainerHigh: Color(0xFFF0F0EE),
  surfaceContainerHighest: Color(0xFFEAEAE7),
  outline: Color(0xFFBFBFBB),
  outlineVariant: Color(0xFFE2E2DE),
);

ThemeData buildNqeTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardTheme(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      // Explicit, identical padding so TextField and DropdownButtonFormField
      // render at the SAME height and line up when placed side-by-side.
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
      selectedItemColor: scheme.onSurface,
      unselectedItemColor: scheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

/// Holds and persists the app's light/dark preference.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    _mode = switch (v) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
        ThemeMode.dark => 'dark',
      },
    );
  }
}

final ThemeController themeController = ThemeController();
