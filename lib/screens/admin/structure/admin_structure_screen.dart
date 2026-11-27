import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/constants/course_catalogue.dart';
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

  /// Names changed before adding, and units left out, by course code.
  final Map<String, String> _renamed = {};
  final Set<String> _skipped = {};

  /// Kept so that typing or ticking does not reload the list.
  Stream<List<Subject>>? _subjects;
  ProgramType? _subjectsTrack;

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

  Future<String?> _askName(String current) => showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(current),
      );

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addUnits(Map<CourseUnit, String> units) async {
    setState(() => _isSubmitting = true);
    try {
      await _repository.addStandardSubjects(
        programType: _selectedTrack!,
        year: _selectedYear!,
        semester: _selectedSemester!,
        units: units,
      );
      if (mounted) _say('Added ${units.length} subjects.');
    } catch (_) {
      if (mounted) _say('Could not add the subjects. Check your connection.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _editSubject(Subject subject) async {
    final name = await _askName(subject.name);
    if (name == null || name == subject.name || !mounted) return;
    try {
      await _repository.renameSubject(subject.id, name);
    } catch (_) {
      if (mounted) _say('Could not save the change. Check your connection.');
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
    final track = _selectedTrack;
    if (track != null && track != _subjectsTrack) {
      _subjectsTrack = track;
      _subjects = _repository.watchSubjectsForTrack(track);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Academic Structure')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            _buildSubjectList(),
          ],
        ),
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
      key: ValueKey(track),
      stream: _subjects,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingIndicator();
        }
        if (snapshot.hasError) {
          return AppErrorDisplay(
            failure: UnknownFailure(snapshot.error.toString()),
          );
        }

        final year = _selectedYear;
        final semester = _selectedSemester;
        final subjects = [
          for (final s in snapshot.data ?? <Subject>[])
            if ((year == null || s.year == year) &&
                (semester == null || s.semester == semester))
              s,
        ]..sort((a, b) {
            if (a.year != b.year) return a.year - b.year;
            if (a.semester != b.semester) return a.semester - b.semester;
            return a.name.compareTo(b.name);
          });

        // Matched against the whole track, so a unit moved to another class
        // is not offered (and overwritten) again.
        final all = [
          for (final s in snapshot.data ?? <Subject>[])
            (id: s.id, name: s.name),
        ];
        final missing = year == null || semester == null
            ? <CourseUnit>[]
            : [
                for (final unit in standardUnits(track, year, semester))
                  if (!hasUnit(track, unit, all)) unit,
              ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (missing.isNotEmpty) ..._buildStandardUnits(missing),
            if (subjects.isEmpty && missing.isEmpty)
              const AppEmptyState(
                icon: Icons.inbox_outlined,
                title: 'No subjects yet',
                message: 'Subjects created for this track will appear here.',
              ),
            if (subjects.isNotEmpty) _heading('Subjects added'),
            for (final subject in subjects)
              ListTile(
                title: Text(subject.name),
                subtitle: Text(
                  'Year ${subject.year} · Semester ${subject.semester}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit subject',
                      onPressed: () => _editSubject(subject),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete subject',
                      onPressed: () => _confirmDeleteSubject(subject),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  /// The catalogue units this class does not have yet.
  List<Widget> _buildStandardUnits(List<CourseUnit> missing) {
    final chosen = {
      for (final unit in missing)
        if (!_skipped.contains(unit.code))
          unit: _renamed[unit.code] ?? unit.subjectName,
    };
    return [
      _heading('Standard course units'),
      for (final unit in missing)
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: !_skipped.contains(unit.code),
          onChanged: _isSubmitting
              ? null
              : (ticked) => setState(() {
                    ticked == true
                        ? _skipped.remove(unit.code)
                        : _skipped.add(unit.code);
                  }),
          title: Text(_renamed[unit.code] ?? unit.subjectName),
          secondary: IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Change before adding',
            onPressed: _isSubmitting
                ? null
                : () async {
                    final name = await _askName(
                      _renamed[unit.code] ?? unit.subjectName,
                    );
                    if (name != null && mounted) {
                      setState(() => _renamed[unit.code] = name);
                    }
                  },
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton.icon(
          onPressed: _isSubmitting || chosen.isEmpty
              ? null
              : () => _addUnits(chosen),
          icon: const Icon(Icons.playlist_add_check),
          label: Text('Add selected subjects (${chosen.length})'),
        ),
      ),
    ];
  }
}

/// Returns the new name, or nothing if cancelled.
class _NameDialog extends StatefulWidget {
  final String name;
  const _NameDialog(this.name);

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit subject'),
        content: Form(
          key: _formKey,
          child: AppTextField(
            controller: _controller,
            label: 'Course code and name',
            validator: (v) {
              final length = (v ?? '').trim().length;
              return length < 2 || length > 100 ? 'Enter the name' : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.of(context).pop(_controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
}
