import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../data/models/tutor_account.dart';

/// Reached only via the router guard's redirect, when a signed-in tutor's
/// account status is suspended or terminated (see
/// `core/router/app_router.dart`'s `!auth.isUsableTutorSession` check).
///
/// This is the destination that check was built for back in the router
/// batch — a suspended tutor can't just bounce to login (confusing, it
/// would just fail the same way) or to the dashboard (wrong, that's
/// exactly what's being blocked). This screen exists so the router
/// guard has somewhere honest to send them.
class TutorAccountInactiveScreen extends StatelessWidget {
  const TutorAccountInactiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tutor = context.watch<AuthProvider>().tutorAccount;
    final isTerminated = tutor?.status == AccountStatus.terminated;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block,
                size: 56,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                isTerminated ? 'Account Terminated' : 'Account Suspended',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isTerminated
                    ? 'Your tutor account has been terminated. Contact '
                        'Admin if you believe this is a mistake.'
                    : 'Your tutor account has been suspended by Admin. '
                        'Contact Admin for details.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () async {
                  await context.read<AuthProvider>().signOut();
                  if (context.mounted) context.go(AppRoutes.roleSelect);
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
