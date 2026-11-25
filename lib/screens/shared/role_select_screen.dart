import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/admin_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_loading_indicator.dart';

/// The three-way Admin / Tutor / Student entry point, per Section 2.
///
/// The Admin button's destination is NOT fixed — it depends on whether
/// the single Admin account (Section 2.1) already exists. This screen is
/// the first real caller of AdminRepository.adminExists(), which was
/// built specifically for this check back when AdminRepository was
/// written. Tapping Admin when no account exists yet routes to first-run
/// setup; tapping it afterward routes to ordinary login. Tutor and
/// Student routes are fixed — they don't have this same "does an account
/// already exist" ambiguity, since Tutor always self-registers-or-logs-in
/// and Student never authenticates at all.
class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  final _adminRepository = AdminRepository();
  bool _checkingAdmin = false;

  Future<void> _onAdminTapped() async {
    setState(() => _checkingAdmin = true);
    try {
      final exists = await _adminRepository.adminExists();
      if (!mounted) return;
      // Clear any error left over from a previous, abandoned Login
      // attempt before this fresh navigation — see AuthProvider.
      // clearError's doc comment for why this must happen HERE (at the
      // point of a user-initiated tap) and not inside AdminLoginScreen
      // itself, which also needs to display errors that arrive via
      // router redirect rather than a tap on this screen.
      context.read<AuthProvider>().clearError();
      // push, not go: this is a forward drill-down from role selection,
      // not an auth-state transition — the phone's back button should
      // return to this screen, not fall through to closing the app.
      context.push(exists ? AppRoutes.adminLogin : AppRoutes.adminSetup);
    } catch (e) {
      // Most likely cause right now: no Firebase project connected yet
      // (see main.dart's note on this). Surfacing it as a plain message
      // instead of an uncaught exception/red error screen, since this
      // is an expected, temporary state during early debugging, not a
      // bug in this screen itself.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not reach the server. Is Firebase set up yet? ($e)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingAdmin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RCSN Mobile App')),
      body: _checkingAdmin
          ? const AppLoadingIndicator()
          : Padding(
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
                    label: 'Admin',
                    icon: Icons.admin_panel_settings,
                    onTap: _onAdminTapped,
                  ),
                  const SizedBox(height: 16),
                  _RoleButton(
                    label: 'Tutor',
                    icon: Icons.school,
                    // push, not go — see _onAdminTapped's comment above.
                    // Also clears any stale error for the same reason
                    // as the Admin branch — not yet load-bearing since
                    // TutorLoginScreen doesn't watch AuthProvider.
                    // lastError the way AdminLoginScreen now does, but
                    // correct to include now so it's already right when
                    // that screen is upgraded to match.
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
