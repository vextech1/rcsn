import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

/// The Staff / Tutor / Student entry point.
///
/// "Staff" is the shared login for Principal, Registrar and Bursar; which
/// dashboard they land on is decided after sign-in from their `staff`
/// record. There is no pre-sign-in "does an admin exist" check any more:
/// the Principal is created by a one-time bootstrap script, never in-app.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RCSN Mobile App')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Continue as',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 32),
            _RoleButton(
              label: 'Staff',
              icon: Icons.admin_panel_settings,
              // Clear any error left over from a previous, abandoned
              // login attempt before this fresh navigation. See
              // AuthProvider.clearError for why this happens HERE and
              // not inside the login screen. push, not go: this is a
              // forward drill-down, so back returns to this screen.
              onTap: () {
                context.read<AuthProvider>().clearError();
                context.push(AppRoutes.staffLogin);
              },
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
          ],
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
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.primary),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
