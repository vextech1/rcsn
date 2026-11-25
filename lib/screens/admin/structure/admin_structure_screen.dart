import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/subject.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/academic_structure_picker.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Admin's academic-structure builder — where subjects are created
/// against a specific track/year/semester.
///
/// DESIGN NOTE, not specified anywhere in planning: the list below the
/// create-form is scoped to whichever track is CURRENTLY SELECTED in the
/// form, not a flat list of every Subject across all six tracks. That's
/// a judgment call made here, not a requirement — with six tracks and
/// potentially many subjects each, a flat unscoped list would become
/// unwieldy as a working tool Admin returns to repeatedly. If a flat
/// cross-track view is wanted instead, StructureRepository.
/// watchAllSubjects() already exists and would need to replace the
/// scoped watchSubjectsForTrack() call below.
class AdminStructureScreen extends StatefulWidget {
  const AdminStructureScreen({super.key});

  @override
  State<AdminStructureScreen> createState() => _AdminStructureScreenState();
}

class _AdminStructureScreenState extends State<AdminStructureScreen> {
  final _repository = StructureRepository();
  final _nameController = TextEditingController();

  ProgramType? _selectedTrack;
  int? _selectedYear;
  int? _selectedSemester;

  bool _isSubmitting = false;
  AppFailure? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createSubject() async {
    final name = _nameController.text.trim();

    if (name.isEmpty ||
        _selectedTrack == null ||
        _selectedYear == null ||
        _selectedSemester == null) {
      setState(() {
        _error = const UnknownFailure(
          'Enter a subject name and select track, year, and semester.',
        );
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // This is the concrete point where Subject.hasValidYearSemester
      // (checked internally by createSubject, per StructureRepository's
      // own doc comment) actually gets exercised for the first time —
      // e.g. attempting Certificate + Year 3 + Semester 2 here is
      // exactly the case that should fail, since that track's Year 3
      // has only one semester (Section 3.1).
      await _repository.createSubject(
        name: name,
        programType: _selectedTrack!,
        year: _selectedYear!,
        semester: _selectedSemester!,
      );
      _nameController.clear();
    } on AppFailure catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _confirmDeleteSubject(Subject subject) async {
    // Same class of action as Tutor/Student terminate elsewhere in
    // Admin — destructive and irreversible through this app, so it
    // gets a confirmation dialog rather than a bare delete-on-tap.
    // Per StructureRepository.deleteSubject's own doc comment, this
    // does NOT cascade-delete ContentItems or TutorAssignments that
    // reference this subject — surfacing that here so Admin isn't
    // surprised later by orphaned references this screen can't clean
    // up on its own.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this subject?'),
        content: Text(
          '"${subject.name}" (Year ${subject.year}, Semester '
          '${subject.semester}) will be removed. Any content or tutor '
          'assignments already linked to it will NOT be cleaned up '
          'automatically. This cannot be undone through this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteSubject(subject.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete subject: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Academic Structure')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add a Subject',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AcademicStructurePicker(
                      initialTrack: _selectedTrack,
                      initialYear: _selectedYear,
                      initialSemester: _selectedSemester,
                      onChanged: (track, year, semester) {
                        setState(() {
                          _selectedTrack = track;
                          _selectedYear = year;
                          _selectedSemester = semester;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _nameController,
                      label: 'Subject Name',
                      error: _error,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _createSubject,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create Subject'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildSubjectList()),
        ],
      ),
    );
  }

  Widget _buildSubjectList() {
    final track = _selectedTrack;
    if (track == null) {
      return const AppEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Select a track',
        message: 'Choose a track above to see its existing subjects.',
      );
    }

    return StreamBuilder<List<Subject>>(
      stream: _repository.watchSubjectsForTrack(track),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingIndicator();
        }
        if (snapshot.hasError) {
          return AppErrorDisplay(
            failure: UnknownFailure(snapshot.error.toString()),
          );
        }

        final subjects = snapshot.data ?? [];
        if (subjects.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No subjects yet',
            message: 'Subjects created for this track will appear here.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: subjects.length,
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return ListTile(
              title: Text(subject.name),
              subtitle:
                  Text('Year ${subject.year} · Semester ${subject.semester}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete subject',
                onPressed: () => _confirmDeleteSubject(subject),
              ),
            );
          },
        );
      },
    );
  }
}
