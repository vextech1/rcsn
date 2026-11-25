import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';

/// The Admin landing screen.
///
/// Deliberately scoped as pure navigation, not a data-summary dashboard.
/// Per Section 2.1, Admin's actual responsibilities are: building
/// academic structure, managing tutors/assignments, entering students at
/// admission, and managing content-type categories. This screen routes
/// to each of those four work areas rather than trying to show live
/// counts or previews of all four inline — that would mean this single
/// screen depends on four separate Firestore streams just to render a
/// summary nobody specifically asked for, and would slow down the very
/// first screen Admin sees after signing in. Each destination screen
/// owns its own data loading.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) context.go(AppRoutes.roleSelect);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _DashboardTile(
              icon: Icons.account_tree,
              label: 'Academic Structure',
              // push, not go: this is a forward drill-down from the
              // dashboard, not an auth-state transition — the phone's
              // back button should return to the dashboard, not fall
              // through to closing the app. This is the exact bug
              // reported after creating a subject on this screen and
              // pressing back. Sign-out below, in contrast, correctly
              // stays go() — after signing out, Admin should NOT be
              // able to back into the dashboard.
              onTap: () => context.push(AppRoutes.adminStructure),
            ),
            _DashboardTile(
              icon: Icons.school,
              label: 'Tutors',
              onTap: () => context.push(AppRoutes.adminTutors),
            ),
            _DashboardTile(
              icon: Icons.people,
              label: 'Students',
              onTap: () => context.push(AppRoutes.adminStudents),
            ),
            _DashboardTile(
              icon: Icons.category,
              label: 'Content Types',
              onTap: () => context.push(AppRoutes.adminContentTypes),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
