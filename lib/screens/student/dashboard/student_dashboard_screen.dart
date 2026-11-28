import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/subject.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// The student's landing screen after a successful NSIN lookup.
///
/// Shows the student's academic identity (name, program, year, semester)
/// and the list of subjects scoped to their track/year/semester. This
/// is the read-only view — the student sees content but cannot upload
/// or archive (those are tutor-only actions per Section 2.4).
///
/// SUBJECT SCOPING: a student sees only subjects matching their
/// [StudentRecord.programType], [StudentRecord.year], AND
/// [StudentRecord.semester]. [StructureRepository.watchSubjectsForTrack]
/// returns all subjects for the track; this screen filters client-side
/// by year and semester. The list is live — if Admin adds a new subject
/// to this scope, it appears automatically.
///
/// SETTINGS: the AppBar gear icon navigates to
/// [StudentSettingsScreen], where the student can view their NSIN and
/// clear their session (the borrowed-phone solution described in
/// [StudentProvider]'s doc comment).
///
/// FCM TOKEN REGISTRATION: on first build, this screen registers the
/// device's FCM token in the `student_devices` Firestore collection.
/// This is what enables the Cloud Function (onContentUploaded) to send
/// push notifications to this specific student when a tutor uploads
/// content to one of their subjects. Token registration is best-effort —
/// failure (e.g. permission denied, no network) does not block the
/// dashboard from rendering.
class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  StreamSubscription<String>? _tokenRefreshSubscription;

  @override
  void initState() {
    super.initState();
    _registerDeviceToken();
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  /// Registers this device's FCM token in Firestore so the Cloud
  /// Function can send push notifications to this student.
  ///
  /// Tokens live in the `student_devices` collection — separate from
  /// `students` — to keep the `students` collection purely academic
  /// data, matching [StudentRecord]'s own scope-boundary constraint.
  ///
  /// Also subscribes to [NotificationService.onTokenRefresh] to update
  /// the stored token whenever FCM rotates it. Without this, push
  /// notifications silently stop reaching the device after rotation.
  Future<void> _registerDeviceToken() async {
    try {
      final student = context.read<StudentProvider>().currentStudent;
      if (student == null) return;

      final notificationService = NotificationService();
      final hasPermission = await notificationService.requestPermission();
      if (!hasPermission) return;

      final token = await notificationService.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection('student_devices')
          .doc(student.id)
          .set({
            'tokens': FieldValue.arrayUnion([token]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      _tokenRefreshSubscription =
          notificationService.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection('student_devices')
            .doc(student.id)
            .set({
              'tokens': FieldValue.arrayUnion([newToken]),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      });
    } catch (_) {
      // Best-effort: never block the dashboard UI over notification
      // registration failure. A failed registration means this student
      // won't get push notifications for new uploads, but the rest of
      // the app works normally.
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>().currentStudent;

    if (student == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Student Dashboard')),
        body: const AppErrorDisplay(
          failure: UnknownFailure(
            'No active student session. Please enter your student number to '
            'continue.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${student.name.split(' ').first}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Timetables',
            onPressed: () => context.push(AppRoutes.studentTimetables),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () =>
                context.push(AppRoutes.studentSettings),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StudentInfoCard(student: student),

          ListTile(
            leading: const Icon(Icons.grading, color: AppColors.primary),
            title: const Text('My coursework results'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.studentResults),
          ),

          ListTile(
            leading: const Icon(Icons.workspace_premium,
                color: AppColors.primary),
            title: const Text('My UHPAB results'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.studentUhpab),
          ),

          ListTile(
            leading: const Icon(Icons.payments, color: AppColors.primary),
            title: const Text('My fees'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.studentFees),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Your Subjects',
              style: AppTypography.heading3(context),
            ),
          ),

          Expanded(
            child: StreamBuilder<List<Subject>>(
              stream: StructureRepository()
                  .watchSubjectsForTrack(student.programType),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingIndicator();
                }

                if (snapshot.hasError) {
                  return AppErrorDisplay(
                    failure: UnknownFailure(snapshot.error.toString()),
                  );
                }

                final allSubjects = snapshot.data ?? [];
                final subjects = allSubjects
                    .where(
                      (s) =>
                          s.year == student.year &&
                          s.semester == student.semester,
                    )
                    .toList();

                if (subjects.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.book_outlined,
                    title: 'No subjects yet',
                    message:
                        'No subjects have been created for your year '
                        'and semester. Check back later or contact '
                        'Admin if you believe this is a mistake.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: subjects.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final subject = subjects[index];
                    return _SubjectTile(
                      subject: subject,
                      onTap: () => context.push(
                        AppRoutes.studentSubject,
                        extra: subject,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Private sub-widgets
// -----------------------------------------------------------------------

/// The student's identity card at the top of the dashboard — name,
/// NSIN (truncated for privacy), program, year, semester.
class _StudentInfoCard extends StatelessWidget {
  final StudentRecord student;

  const _StudentInfoCard({required this.student});

  @override
  Widget build(BuildContext context) {
    final trackLabel = kTrackDefinitions[student.programType]?.label ??
        student.programType.name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.primary.withAlpha(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.name,
            style: AppTypography.heading2(context),
          ),
          const SizedBox(height: 4),
          Text(
            trackLabel,
            style: AppTypography.bodyMuted(context),
          ),
          Text(
            'Year ${student.year} · Semester ${student.semester}',
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Student number: ${_maskNumber(student.nsin)}',
            style: AppTypography.caption(context).copyWith(
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Hides the last three characters of the student number on the dashboard.
  static String _maskNumber(String number) => number.length <= 3
      ? '•••'
      : '${number.substring(0, number.length - 3)}•••';
}

/// A tappable subject row — subject name as the title, no trailing
/// actions (student is read-only).
class _SubjectTile extends StatelessWidget {
  final Subject subject;
  final VoidCallback onTap;

  const _SubjectTile({required this.subject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final trackLabel = kTrackDefinitions[subject.programType]?.label ??
        subject.programType.name;

    return ListTile(
      leading: const Icon(Icons.book_outlined, color: AppColors.primary),
      title: Text(subject.name, style: AppTypography.body(context)),
      subtitle: Text(
        '$trackLabel · Year ${subject.year}, Sem ${subject.semester}',
        style: AppTypography.caption(context),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
