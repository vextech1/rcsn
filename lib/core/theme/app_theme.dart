import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Both light and dark ThemeData for the app.
///
/// AUDIT NOTE: this file previously lost several pieces during an
/// undocumented rewrite between handoffs — the private constructor, the
/// AppTypography-based TextTheme (replaced with a generic
/// Typography.material2021() that has no link back to kAppFontFamily),
/// and the explicit component themes (buttons, input fields, cards).
/// Restored here, alongside the new dark theme this file was extended
/// with — doing both together rather than patching dark mode onto the
/// thinner version, since touching this file twice for related reasons
/// serves no one.
///
/// DARK THEME DESIGN NOTE: AppColors' values (primary especially, a
/// deep slate-blue) were built as LIGHT-mode colors — used directly as a
/// dark-mode primary against a near-black background, they read as
/// murky rather than vibrant; dark mode needs the same brand HUE
/// lightened enough to stay legible on dark surfaces, not a naive
/// inversion of the light palette's lightness values. Rather than hand-
/// pick a second full palette (impossible to verify visually from this
/// environment), both themes use the same seeded approach:
/// ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: ...)
/// — Material 3's algorithm derives an appropriate tonal palette for
/// each brightness from one seed, which is also consistent with how
/// the light theme was already built, rather than introducing a second,
/// different theming strategy just for dark mode.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      // Light mode pins these to the exact brand hex values (see the
      // original FIXED comment this file carried: default-styled
      // widgets must match the same brand color used everywhere else,
      // not Material3's algorithmic approximation of it).
      //
      // Dark mode deliberately does NOT pin to the same light-mode
      // hexes — that's the "murky, not vibrant" problem described in
      // the class doc above. Dark mode keeps ColorScheme.fromSeed's own
      // derived tones for primary/secondary, which are already
      // correctly lightened for a dark surface, and only overrides
      // error (a fixed brand/semantic color that shouldn't shift with
      // brightness).
      primary: isDark ? null : AppColors.primary,
      secondary: isDark ? null : AppColors.secondary,
      error: AppColors.error,
      surface: isDark ? null : AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? colorScheme.surface : AppColors.background,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark ? colorScheme.surface : AppColors.primary,
        foregroundColor:
            isDark ? colorScheme.onSurface : AppColors.surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          // Was `AppTypography.button` (now a method requiring
          // BuildContext, which this file has no access to — _buildTheme
          // only receives Brightness, not context). foregroundColor
          // above already correctly supplies this button's text COLOR
          // for both light and dark mode, so textStyle here only needs
          // font properties — deliberately colorless, matching
          // AppTypography.button's font values (fontSize: 15,
          // fontWeight: w600) without its color, since that color would
          // be wrong here anyway (button() always resolves to
          // onPrimary-equivalent regardless of brightness, which happens
          // to match, but relying on that coincidence would be fragile).
          textStyle: const TextStyle(
            fontFamily: kAppFontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      // NOTE: no textTheme: block here anymore. This file previously had
      // one that called AppTypography.heading1.copyWith(...) etc. — that
      // was written BEFORE AppTypography's tokens were converted from
      // static const properties to static methods taking BuildContext
      // (see app_typography.dart's own class doc for why: dark-mode
      // color resolution needed to happen at render time, not compile
      // time). This file was never updated after that conversion, so it
      // was calling .copyWith() on a Function — a genuine compile error,
      // not a lint. Since AppTypography's methods now resolve their own
      // brightness-correct color internally via Theme.of(context)
      // directly at each call site (AppTypography.body(context), etc.),
      // ThemeData.textTheme no longer needs to duplicate that work here
      // — removing this block is the fix, not reconstructing it to call
      // AppTypography.heading1(context) instead, since screens already
      // call AppTypography's methods directly rather than through
      // Theme.of(context).textTheme.headlineMedium.
    );
  }
}
