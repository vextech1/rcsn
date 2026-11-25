import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/dashboard_tile.dart';

/// The Principal landing screen.
///
/// The Principal's own responsibility is staff management. The four
/// academic tiles are TEMPORARY: until Phase 2 gives the Principal a
/// read-only view of them, the Principal keeps access to the screens the
/// single Admin used to have, so nothing is lost while there is no
/// Registrar yet.
class PrincipalDashboardScreen extends StatelessWidget {
  const PrincipalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Principal'),
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
            DashboardTile(
              icon: Icons.badge,
              label: 'Staff',
              onTap: () => context.push(AppRoutes.principalStaff),
            ),
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
            DashboardTile(
              icon: Icons.category,
              label: 'Content Types',
              onTap: () => context.push(AppRoutes.registrarContentTypes),
            ),
          ],
        ),
      ),
    );
  }
}
