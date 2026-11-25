import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../data/models/tutor_account.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_error_display.dart';

/// Reached only via the router guard's redirect, when a student's NSIN
/// lookup succeeds but their account status is suspended or terminated.
///
/// Same architectural role as [TutorAccountInactiveScreen] — the router
/// guard needs a destination to send a student whose session exists but
/// is not usable. Without this screen, a suspended student would bounce
/// between the search screen and the dashboard with no explanation.
///
/// The clear-session action here is important: a suspended/terminated
/// student still needs a way to clear their NSIN from the device so
/// another student can use it (the borrowed-phone scenario). This
/// screen provides that path without routing through the dashboard.
class StudentAccountInactiveScreen extends StatelessWidget {
  const StudentAccountInactiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>().currentStudent;

    if (student == null) {
      return Scaffold(
        body: const AppErrorDisplay(
          failure: UnknownFailure('No student session found.'),
        ),
      );
    }

    final isTerminated = student.status == AccountStatus.terminated;

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
                isTerminated ? 'Course Terminated' : 'Account Suspended',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isTerminated
                    ? 'Your course enrolment has been terminated. '
                        'Contact the school administration if you '
                        'believe this is a mistake.'
                    : 'Your account has been suspended. Contact the '
                        'school administration for more information.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text('Clear Session'),
                onPressed: () async {
                  await context.read<StudentProvider>().clearSession();
                  if (context.mounted) {
                    context.go(AppRoutes.studentSearch);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
