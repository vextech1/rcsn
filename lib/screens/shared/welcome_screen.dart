import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// The app's entry point — "Welcome to RCSN Mobile App," per the
/// original brief.
///
/// Uses an explicit tap-to-continue button, confirmed directly — an
/// earlier draft of this screen defaulted to auto-advancing after a
/// delay, flagged at the time as an unconfirmed assumption rather than a
/// specified requirement. That assumption was corrected before this file
/// was written, so no auto-advance timer exists here at all.
///
/// NOTE ON THEME: this screen is deliberately excluded from the app's
/// dark-mode support (see AppTheme's class doc comment) — it's a fixed
/// dark-background hero screen regardless of system theme, using
/// AppColors.primary directly rather than Theme.of(context). It still
/// uses AppTypography tokens (heading2, tagline, button) for the actual
/// font sizes/weights, with colors overridden via .copyWith() at each
/// call site — that's about not duplicating those exact size/weight
/// values a second time, not about responding to theme changes.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The full, uncropped school logo (the same artwork as the
              // launcher icon, minus the adaptive-icon crop). BoxFit.contain
              // keeps its aspect ratio so nothing is clipped or stretched.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260, maxHeight: 240),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    fit: BoxFit.contain,
                    semanticLabel: 'Rakai Community School of Nursing logo',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to RCSN Mobile App',
                textAlign: TextAlign.center,
                style: AppTypography.heading2(context).copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'WE SERVE FOR BETTER HEALTH',
                style: AppTypography.tagline.copyWith(color: AppColors.accent),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  // push, not go: this is a forward drill-down from the
                  // app's entry screen, not an auth-state transition —
                  // the phone's back button (and any AppBar back arrow
                  // on the next screen) should return here, not fall
                  // through to closing the app. See app_router.dart's
                  // note on this same push-vs-go distinction.
                  onPressed: () => context.push(AppRoutes.roleSelect),
                  child: Text(
                    'Continue',
                    style: AppTypography.button(context).copyWith(
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
