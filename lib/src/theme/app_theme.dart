import 'package:flutter/material.dart';

/// The app's visual system.
///
/// Built from a seed colour rather than hand-picked hex values, so Material 3
/// derives the full tonal palette — including the on-colours and container
/// variants — with contrast ratios that already pass WCAG AA. Hard-coding a
/// palette means hand-checking every foreground/background pair, and that check
/// silently rots the first time someone adds a surface.
///
/// Both brightnesses are provided and the app follows the system setting. A bus
/// helper works in direct Dhaka sun and in a dark cabin at night; forcing either
/// mode makes the screen unreadable in the other half of the day.
class AppTheme {
  const AppTheme._();

  /// Amber reads as "transport / caution" and keeps its punch against both a
  /// white and a near-black surface, which a mid-tone blue does not.
  static const Color _seed = Color(0xFFF59E0B);

  /// Reserved for genuine go/stop meaning — an active trip, a live connection.
  /// Never decoration: if green stops meaning "running", the dashboard stops
  /// being readable at a glance.
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);

  /// Minimum tappable edge. Material specifies 48dp; this is deliberately
  /// larger because the target user is standing in a moving vehicle.
  static const double minTouchTarget = 56;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Layout breakpoints, in logical pixels of *width*.
///
/// The fleet's phones range from 320dp budget Androids to 430dp flagships, and
/// a fixed layout that fits one clips the other. Anything laid out in a row —
/// the dashboard's stat tiles, the emergency buttons — checks this first.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// True on the narrow end (iPhone SE, Galaxy A0x and similar), where a
  /// two-column grid of large numbers starts to wrap mid-word.
  bool get isCompact => screenWidth < 360;

  /// Horizontal page padding that stays proportionate instead of eating half
  /// the screen on a small device.
  EdgeInsets get pagePadding =>
      EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20);

  /// Caps how far the user's font-size setting can scale our large numerals.
  /// Accessibility settings must be honoured, but a 4x-scaled "42/50" overflows
  /// its tile and becomes less readable, not more.
  TextScaler get cappedTextScaler =>
      MediaQuery.textScalerOf(this).clamp(maxScaleFactor: 1.6);
}
