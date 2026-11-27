import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/dashboard_tile.dart';

/// Landing screen for staff in a custom position (Askari, Accountant,
/// Clinical Instructor, ...).
///
/// These positions have no management powers. For now they can sign in and
/// read the Public Space; what each position can do beyond that is decided
/// later, per position.
class StaffMemberDashboardScreen extends StatelessWidget {
  const StaffMemberDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AuthProvider>().staffAccount;

    return Scaffold(
      appBar: AppBar(
        title: Text(staff?.positionLabel ?? 'Staff'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${staff?.name ?? ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(staff?.positionLabel ?? ''),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  DashboardTile(
                    icon: Icons.campaign,
                    label: 'Public Space',
                    onTap: () => context.push(AppRoutes.publicHome),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
