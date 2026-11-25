import 'package:flutter/material.dart';

/// Typography per Section 7.5 of the project document: a clean, highly
/// legible sans-serif for all UI text. The crest carries its own
/// decorative weight and is never paired with a matching decorative
/// typeface — UI text stays plain and functional.
///
/// Font family: Roboto. Font files (Roboto-Regular/Medium/Bold.ttf) are
/// declared in pubspec.yaml under assets/fonts/ — added manually rather
/// than by Claude, so if text is rendering with a fallback system font
/// instead of true Roboto, check that those three files actually exist
/// at that path before assuming this constant is wrong. Medium (500) is
/// bundled specifically because AppTypography uses FontWeight.w600 in
/// several styles below (heading3, button, overline) — without a real
/// Medium file, Flutter fakes w600 by synthetically "bolding" Regular,
/// a visible quality difference from actual Medium-weight glyphs.
const String kAppFontFamily = 'Roboto';

/// CHANGED (2026-07, dark-mode support): every token below used to be a
/// `static const TextStyle` with a color baked in directly from
/// [AppColors] — always the light-mode value, regardless of the phone's
/// system theme. That made dark mode impossible to support without
/// touching every screen individually: even with a correct dark
/// `ThemeData` wired up, every `Text` styled via `AppTypography.body`
/// would still render dark-on-dark, illegibly, because the color was
/// fixed at compile time rather than resolved at render time.
///
/// Every token is now a METHOD taking [BuildContext], not a property —
/// `AppTypography.body(context)` instead of `AppTypography.body`. Color
/// comes from `Theme.of(context).colorScheme`, which IS brightness-aware
/// once both `AppTheme.lightTheme` and `AppTheme.darkTheme` seed and
/// override that ColorScheme correctly (see app_theme.dart) — so the
/// same call site now renders correctly in both modes with zero
/// per-screen logic. This did require updating every existing call site
/// from `AppTypography.X` to `AppTypography.X(context)`; that mechanical
/// change touched ~20 files but the token names and their font-size/
/// weight/letter-spacing values are all unchanged from before.
class AppTypography {
  AppTypography._();

  static TextStyle heading1(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      );

  static TextStyle heading2(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.secondary,
      );

  static TextStyle heading3(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.4,
      );

  static TextStyle bodyMuted(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  static TextStyle caption(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  static TextStyle button(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onPrimary,
      );

  /// Small uppercase eyebrow/section label — e.g. "SELECT FILE",
  /// "ACCOUNT" grouping headers above a form section.
  static TextStyle overline(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      );

  /// Heading for a form embedded in a Card (e.g. "Add a Subject",
  /// "Register a Student").
  static TextStyle cardTitle(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Full-screen intro heading (e.g. "Create your tutor account").
  static TextStyle screenTitle(BuildContext context) => TextStyle(
        fontFamily: kAppFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Small italicized tagline — WelcomeScreen's "WE SERVE FOR BETTER
  /// HEALTH" line beneath the app name. Used exactly once.
  ///
  /// DELIBERATELY NOT a method like every other token above — it has no
  /// baked-in [color] to resolve from Theme in the first place (color is
  /// supplied via `.copyWith()` at the call site), so there's nothing
  /// context-dependent about it. That's not an oversight: WelcomeScreen
  /// is a fixed-dark-background screen (AppColors.primary, regardless of
  /// system light/dark mode) rather than a theme-reactive one — see
  /// AppTheme's class doc comment on why WelcomeScreen is excluded from
  /// dark-mode support entirely. Giving this token a phantom
  /// [BuildContext] parameter it never uses would misrepresent it as
  /// theme-aware when it structurally can't be.
  static const TextStyle tagline = TextStyle(
    fontFamily: kAppFontFamily,
    fontSize: 13,
    fontStyle: FontStyle.italic,
    letterSpacing: 1,
  );
}
