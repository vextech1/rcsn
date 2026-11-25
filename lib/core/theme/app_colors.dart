import 'package:flutter/material.dart';

/// Color palette per Section 7.4 of the project document.
///
/// These are muted, desaturated adaptations of RCSN's actual crest colors
/// (sky blue / green / gold) — deliberately more refined than the source
/// logo, matching the formal/institutional tone confirmed throughout
/// planning. The doc flagged these as directional, not final: confirm
/// against real rendered UI before treating them as permanent. Swap the
/// hex values below if a closer visual match to the physical crest is
/// wanted once seen on-device.
class AppColors {
  AppColors._();

  /// Deep, desaturated slate-blue — from the crest's main circular field.
  static const Color primary = Color(0xFF1F4E5F);
  static const Color primaryLight = Color(0xFF3A7186);
  static const Color primaryDark = Color(0xFF14343F);

  /// Muted forest green — from the crest's outer ring and ribbon.
  static const Color secondary = Color(0xFF3A5F3A);
  static const Color secondaryLight = Color(0xFF577D57);

  /// Softened gold/ochre — from the crest's staff (Rod of Asclepius).
  /// Used sparingly per the branding doc: active states, highlights,
  /// notification badges — not as a dominant color.
  static const Color accent = Color(0xFFA67C2E);

  /// Near-black, slightly warm — from the crest's cobra and text linework.
  static const Color textDark = Color(0xFF222222);
  static const Color textMid = Color(0xFF555555);

  static const Color background = Color(0xFFF7F7F5);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E6B3E);
  static const Color warning = Color(0xFFA67C2E); // same as accent — deliberate, keeps warning states visually tied to the brand gold rather than an unrelated orange
}
