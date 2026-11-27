import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';

/// The Staff / Tutor / Student entry point.
///
/// "Staff" is the shared login for Principal, Registrar and Bursar; which
/// dashboard they land on is decided after sign-in from their `staff`
/// record. There is no pre-sign-in "does an admin exist" check any more:
/// the Principal is created by a one-time bootstrap script, never in-app.
///
/// NOTE ON THEME: like the welcome screen this is deliberately a fixed
/// brand-colour hero screen regardless of system light/dark mode: solid
/// AppColors.primary background, white text, white buttons with primary-
/// coloured labels. Colours are set explicitly here rather than read from
/// Theme.of(context), so the two entry screens always look like one flow.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_hospital,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                'Continue as',
                textAlign: TextAlign.center,
                style: AppTypography.heading2(context).copyWith(color: Colors.white),
              ),
              const SizedBox(height: 40),
              _RoleButton(
                label: 'Staff',
                icon: Icons.admin_panel_settings,
                // Staff pick their position first (the list is on the next
                // screen), then sign in. That screen clears any stale login
                // error. push, not go: this is a forward drill-down, so back
                // returns to this screen.
                onTap: () => context.push(AppRoutes.staffPositions),
              ),
              const SizedBox(height: 16),
              _RoleButton(
                label: 'Tutor',
                icon: Icons.school,
                onTap: () {
                  context.read<AuthProvider>().clearError();
                  context.push(AppRoutes.tutorLogin);
                },
              ),
              const SizedBox(height: 16),
              _RoleButton(
                label: 'Student',
                icon: Icons.person,
                onTap: () => context.push(AppRoutes.studentSearch),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => context.push(AppRoutes.publicHome),
                  icon: const Icon(Icons.public),
                  label: Text(
                    'Continue without login',
                    style: AppTypography.button(context).copyWith(
                      fontSize: 16,
                      color: Colors.white,
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

class _RoleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Same look as the welcome screen's Continue button: white fill,
    // primary-coloured label.
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.primary),
        label: Text(
          label,
          style: AppTypography.button(context).copyWith(
            fontSize: 16,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
