import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/app_empty_state.dart';

/// Bursar landing screen. Placeholder until the fees module is built in
/// Phase 3 (student list, record payment, balances).
class BursarDashboardScreen extends StatelessWidget {
  const BursarDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bursar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Public Space',
            onPressed: () => context.push(AppRoutes.publicHome),
          ),
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
      body: const AppEmptyState(
        icon: Icons.payments,
        title: 'Fees are coming soon',
        message:
            'Recording payments and viewing student balances will appear '
            'here once the fees module is ready.',
      ),
    );
  }
}
