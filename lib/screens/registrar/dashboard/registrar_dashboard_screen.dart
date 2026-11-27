import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/dashboard_tile.dart';

/// The Registrar landing screen.
///
/// Pure navigation, not a data-summary dashboard: each destination screen
/// owns its own data loading, so the first screen after sign-in stays fast.
/// The four work areas are the original Admin screens, which Phase 2
/// rebuilds for the Registrar.
class RegistrarDashboardScreen extends StatelessWidget {
  const RegistrarDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar'),
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
            // push, not go: forward drill-down, so the back button
            // returns here. Sign-out stays go() so nobody can back into
            // the dashboard after signing out.
            DashboardTile(
              icon: Icons.account_tree,
              label: 'Academic Structure',
              onTap: () => context.push(AppRoutes.registrarStructure),
            ),
            DashboardTile(
              icon: Icons.school,
              label: 'Tutors',
              onTap: () => context.push(AppRoutes.registrarTutors),
            ),
            DashboardTile(
              icon: Icons.people,
              label: 'Students',
              onTap: () => context.push(AppRoutes.registrarStudents),
            ),
            // Only the Registrar may change it; the rules agree.
            if (context.watch<AuthProvider>().resolvedRole ==
                UserRole.registrar)
              DashboardTile(
                icon: Icons.pin,
                label: 'Student Number Format',
                onTap: () => context.push(AppRoutes.registrarStudentNumber),
              ),
            DashboardTile(
              icon: Icons.category,
              label: 'Content Types',
              onTap: () => context.push(AppRoutes.registrarContentTypes),
            ),
            DashboardTile(
              icon: Icons.calendar_month,
              label: 'Timetables',
              onTap: () => context.push(AppRoutes.registrarTimetables),
            ),
            DashboardTile(
              icon: Icons.campaign,
              label: 'Public Space',
              onTap: () => context.push(AppRoutes.publicHome),
            ),
          ],
        ),
      ),
    );
  }
}
