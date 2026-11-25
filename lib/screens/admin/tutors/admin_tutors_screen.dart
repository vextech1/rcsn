import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/tutor_account.dart';
import '../../../data/models/subject.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../providers/tutor_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/academic_structure_picker.dart';

/// Admin's tutor management screen — lists every registered tutor with
/// their account status, and provides the assignment flow.
///
/// This is the concrete UI for the self-register-but-cannot-self-assign
/// boundary described in TutorRepository's own doc comment: a tutor
/// shows up in this list the moment they register (Section 2.2), with
/// zero subjects assigned, and stays that way until Admin explicitly
/// assigns them here. There is deliberately no "assign yourself" action
/// anywhere a tutor could reach — assignment only exists on THIS screen,
/// which per the app's route guards (core/router/app_router.dart) is
/// only reachable as an authenticated Admin.
class AdminTutorsScreen extends StatefulWidget {
  const AdminTutorsScreen({super.key});

  @override
  State<AdminTutorsScreen> createState() => _AdminTutorsScreenState();
}

class _AdminTutorsScreenState extends State<AdminTutorsScreen> {
  final _tutorProvider = TutorProvider();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutors')),
      body: StreamBuilder<List<TutorAccount>>(
        stream: _tutorProvider.watchAllTutors(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator();
          }
          if (snapshot.hasError) {
            return AppErrorDisplay(
              failure: UnknownFailure(snapshot.error.toString()),
            );
          }

          final tutors = snapshot.data ?? [];
          if (tutors.isEmpty) {
            return const AppEmptyState(
              icon: Icons.school_outlined,
              title: 'No tutors yet',
              message: 'Tutors will appear here once they register.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: tutors.length,
            itemBuilder: (context, index) {
              return _TutorTile(
                tutor: tutors[index],
                tutorProvider: _tutorProvider,
              );
            },
          );
        },
      ),
    );
  }
}

class _TutorTile extends StatelessWidget {
  final TutorAccount tutor;
  final TutorProvider tutorProvider;

  const _TutorTile({required this.tutor, required this.tutorProvider});

  Color _statusColor() {
    switch (tutor.status) {
      case AccountStatus.active:
        return Colors.green;
      case AccountStatus.suspended:
        return Colors.orange;
      case AccountStatus.terminated:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(tutor.name),
      subtitle: Text(tutor.email),
      trailing: Chip(
        label: Text(
          tutor.status.name,
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
        backgroundColor: _statusColor(),
        padding: EdgeInsets.zero,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add_link),
                label: const Text('Assign to Subject'),
                onPressed: () => _showAssignDialog(context),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildStatusToggleButton()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: tutor.status == AccountStatus.terminated
                          ? null
                          : () => _confirmTerminate(context),
                      child: const Text('Terminate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Returns the left-hand status-change button, which is genuinely
  /// DIFFERENT depending on current status — not a single "Suspend"
  /// button that merely goes disabled. A suspended tutor should see
  /// "Reactivate," not a Suspend button they can't press, since showing
  /// a disabled action that's already true is less clear than showing
  /// the actual next available action.
  Widget _buildStatusToggleButton() {
    if (tutor.status == AccountStatus.suspended) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green,
          side: const BorderSide(color: Colors.green),
        ),
        onPressed: () => tutorProvider.updateTutorStatus(
          tutorId: tutor.id,
          status: AccountStatus.active,
        ),
        child: const Text('Reactivate'),
      );
    }

    return OutlinedButton(
      onPressed: tutor.status == AccountStatus.terminated
          ? null // a terminated tutor has no path back through this
          // screen at all — Reactivate only applies to suspended,
          // not terminated. Whether a terminated account should ever
          // be reversible is a bigger question than this button fix
          // and wasn't part of what was just confirmed — leaving
          // terminated as a true dead end for now, consistent with
          // "cannot be undone through this app" already stated in
          // the terminate confirmation dialog.
          : () => tutorProvider.updateTutorStatus(
                tutorId: tutor.id,
                status: AccountStatus.suspended,
              ),
      child: const Text('Suspend'),
    );
  }

  Future<void> _confirmTerminate(BuildContext context) async {
    // Terminate is destructive and, per how the rest of this app treats
    // account status, effectively permanent in practice — same class of
    // action as archive/delete elsewhere in the app that warranted a
    // confirmation step. Suspend, above, has no confirmation dialog since
    // it's reversible — see _buildStatusToggleButton, which shows
    // "Reactivate" in place of "Suspend" once a tutor is suspended, so
    // Admin has a real path back to active without needing this
    // confirmation flow at all. Terminate has no equivalent reverse path
    // — see _buildStatusToggleButton's own comment on why that's left as
    // a deliberate dead end for now.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminate this tutor?'),
        content: Text(
          '${tutor.name} will lose all access. This cannot be undone '
          'through this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await tutorProvider.updateTutorStatus(
        tutorId: tutor.id,
        status: AccountStatus.terminated,
      );
    }
  }

  Future<void> _showAssignDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => _AssignSubjectDialog(
        tutorId: tutor.id,
        tutorProvider: tutorProvider,
      ),
    );
  }
}

/// The assignment dialog — reuses AcademicStructurePicker for track/year/
/// semester, then adds a subject dropdown scoped to that selection, since
/// "which subject" wasn't something the shared picker itself covers (it
/// stops at semester; subject selection is specific to this assignment
/// context and to the student admission-entry screen, not shared by the
/// structure-builder screen, which creates subjects rather than
/// selecting among existing ones).
class _AssignSubjectDialog extends StatefulWidget {
  final String tutorId;
  final TutorProvider tutorProvider;

  const _AssignSubjectDialog({
    required this.tutorId,
    required this.tutorProvider,
  });

  @override
  State<_AssignSubjectDialog> createState() => _AssignSubjectDialogState();
}

class _AssignSubjectDialogState extends State<_AssignSubjectDialog> {
  final _structureRepository = StructureRepository();

  ProgramType? _track;
  Subject? _selectedSubject;
  bool _isSubmitting = false;
  AppFailure? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign to Subject'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AcademicStructurePicker(
              onChanged: (track, year, semester) {
                setState(() {
                  _track = track;
                  _selectedSubject = null; // reset — subjects depend on track
                });
              },
            ),
            const SizedBox(height: 12),
            if (_track != null)
              StreamBuilder<List<Subject>>(
                stream: _structureRepository.watchSubjectsForTrack(_track!),
                builder: (context, snapshot) {
                  final subjects = snapshot.data ?? [];
                  if (subjects.isEmpty) {
                    return const Text(
                      'No subjects exist yet for this track — create one '
                      'first under Academic Structure.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    );
                  }
                  return DropdownButtonFormField<Subject>(
                    initialValue: _selectedSubject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    items: subjects
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                '${s.name} (Y${s.year} S${s.semester})',
                              ),
                            ))
                        .toList(),
                    onChanged: (s) => setState(() => _selectedSubject = s),
                  );
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!.message, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSubmitting || _selectedSubject == null
              ? null
              : _assign,
          child: const Text('Assign'),
        ),
      ],
    );
  }

  Future<void> _assign() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.tutorProvider.assignTutorToSubject(
        tutorId: widget.tutorId,
        subjectId: _selectedSubject!.id,
      );
      if (mounted) Navigator.pop(context);
    } on AppFailure catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
