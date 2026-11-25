import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../data/models/subject.dart';
import '../../../data/models/tutor_assignment.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tutor_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// Tutor's landing screen after login/registration.
///
/// ROUTE NOTE: `AppRoutes.tutorNotAssigned` exists as a declared path but
/// is deliberately never navigated to from here or anywhere else. Per
/// TutorProvider's own doc comment on [TutorProvider.watchOwnAssignments]:
/// "An empty list here IS the 'Not yet assigned, contact Admin' state...
/// the dashboard screen should treat empty-list, not a separate flag, as
/// the trigger for that empty state." A separate route would mean a
/// second place that state could get out of sync with the live
/// assignments stream — this screen shows that state INLINE instead,
/// reacting to the same stream in real time (the moment Admin assigns a
/// subject, this screen's StreamBuilder updates without a navigation
/// event). `tutorNotAssigned` is left in app_routes.dart as a known-dead
/// path rather than silently deleted, since removing a declared route
/// constant is a bigger, separate cleanup decision than this screen's
/// own job.
class TutorDashboardScreen extends StatefulWidget {
  const TutorDashboardScreen({super.key});

  @override
  State<TutorDashboardScreen> createState() => _TutorDashboardScreenState();
}

class _TutorDashboardScreenState extends State<TutorDashboardScreen> {
  final _tutorProvider = TutorProvider();
  final _structureRepository = StructureRepository();

  @override
  void dispose() {
    _tutorProvider.dispose();
    super.dispose();
  }

  Future<void> _confirmSelfTerminate(String tutorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terminate your account?'),
        content: const Text(
          'This ends your access to RCSN Mobile App as a tutor. This is '
          'the self-service action from Section 2.2 for a tutor who has '
          'left — it is not reversible by you afterward; only Admin can '
          'reactivate a terminated account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _tutorProvider.selfTerminate(tutorId);
      // No manual navigation — the router guard sees the now-terminated
      // account on the next auth-state/assignment check and redirects
      // to tutorAccountInactive on its own, same pattern as sign-in.
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tutorId = auth.firebaseUser?.uid;
    final tutorName = auth.tutorAccount?.name ?? 'Tutor';

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, $tutorName'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'signOut') {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) context.go(AppRoutes.roleSelect);
              } else if (value == 'terminate' && tutorId != null) {
                _confirmSelfTerminate(tutorId);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'signOut', child: Text('Sign Out')),
              PopupMenuItem(
                value: 'terminate',
                child: Text('Terminate My Account'),
              ),
            ],
          ),
        ],
      ),
      body: tutorId == null
          ? const AppLoadingIndicator()
          : StreamBuilder<List<TutorAssignment>>(
              stream: _tutorProvider.watchOwnAssignments(tutorId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingIndicator();
                }
                if (snapshot.hasError) {
                  return AppErrorDisplay(
                    failure: UnknownFailure(snapshot.error.toString()),
                  );
                }

                final assignments = snapshot.data ?? [];
                if (assignments.isEmpty) {
                  // Section 5 step 5's empty state, triggered by the
                  // stream itself rather than a separate route — see
                  // this file's class doc comment.
                  return const AppEmptyState(
                    icon: Icons.hourglass_empty,
                    title: 'Not yet assigned',
                    message:
                        'Contact Admin to be assigned to a subject. Once '
                        'assigned, it will appear here automatically.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: assignments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _AssignedSubjectTile(
                      assignment: assignments[index],
                      structureRepository: _structureRepository,
                    );
                  },
                );
              },
            ),
    );
  }
}

/// Resolves a [TutorAssignment.subjectId] into the actual [Subject] it
/// points at, via a one-shot fetch per row. Deliberately a separate
/// widget rather than an inline FutureBuilder in the list — keeps the
/// N+1 fetch scoped per-row so a rebuild of one row (e.g. after upload)
/// doesn't imply refetching every other row's subject too.
class _AssignedSubjectTile extends StatelessWidget {
  final TutorAssignment assignment;
  final StructureRepository structureRepository;

  const _AssignedSubjectTile({
    required this.assignment,
    required this.structureRepository,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Subject?>(
      future: structureRepository.getSubjectById(assignment.subjectId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(
            title: Text('Loading...'),
            leading: Icon(Icons.book_outlined),
          );
        }

        final subject = snapshot.data;
        if (subject == null) {
          // The Subject was deleted after this assignment was made —
          // a real, if rare, edge case worth surfacing plainly rather
          // than crashing or showing a blank row.
          return const ListTile(
            title: Text('Subject no longer exists'),
            leading: Icon(Icons.error_outline, color: Colors.orange),
          );
        }

        final trackLabel = kTrackDefinitions[subject.programType]?.label ??
            subject.programType.name;

        return ListTile(
          leading: const Icon(Icons.book_outlined),
          title: Text(subject.name),
          subtitle: Text(
            '$trackLabel · Year ${subject.year}, Sem ${subject.semester}',
          ),
          onTap: () =>
              context.push(AppRoutes.tutorSubject, extra: subject),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: 'Upload content',
                onPressed: () =>
                    context.push(AppRoutes.tutorUpload, extra: subject),
              ),
              IconButton(
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive',
                onPressed: () =>
                    context.push(AppRoutes.tutorArchive, extra: subject),
              ),
            ],
          ),
        );
      },
    );
  }
}
