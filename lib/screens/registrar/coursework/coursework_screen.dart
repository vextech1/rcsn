import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/coursework.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/subject.dart';
import '../../../data/models/tutor_account.dart' show AccountStatus;
import '../../../data/repositories/coursework_repository.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../data/repositories/student_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/academic_structure_picker.dart';

/// The Registrar enters one course unit's coursework for a class, saves it as
/// drafts, publishes it to the students and can recall it.
class CourseworkScreen extends StatefulWidget {
  const CourseworkScreen({super.key});

  @override
  State<CourseworkScreen> createState() => _CourseworkScreenState();
}

/// One student on the class list.
class _Row {
  final String nsin;
  final String name;

  /// What is in the database, null if nothing has been saved.
  CourseworkEntry? saved;

  final Map<String, TextEditingController> fields;

  _Row(this.nsin, this.name, this.saved)
      : fields = {
          for (final part in kCourseworkParts)
            part.key: TextEditingController(
              text: saved?.marks.values[part.key] == null
                  ? ''
                  : CourseworkMarks.format(saved!.marks.values[part.key]!),
            ),
        };

  String? errorFor(CourseworkPart part) =>
      CourseworkMarks.errorFor(part, fields[part.key]!.text);

  bool get isValid => kCourseworkParts.every((p) => errorFor(p) == null);

  /// The marks as typed, leaving out blank and invalid ones.
  CourseworkMarks get marks => CourseworkMarks({
        for (final part in kCourseworkParts)
          if (errorFor(part) == null &&
              fields[part.key]!.text.trim().isNotEmpty)
            part.key: double.parse(fields[part.key]!.text.trim()),
      });

  bool get isChanged =>
      !isValid || !marks.sameAs(saved?.marks ?? const CourseworkMarks());

  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
  }
}

class _CourseworkScreenState extends State<CourseworkScreen> {
  final _repository = CourseworkRepository();

  ProgramType? _track;
  int? _year;
  int? _semester;
  Subject? _subject;
  Future<List<Subject>>? _subjects;
  List<_Row>? _rows;
  AppFailure? _error;
  bool _busy = false;

  /// Counts class list loads, so that a slow one cannot replace a newer one.
  int _load = 0;

  bool get _dirty => _rows?.any((r) => r.isChanged) ?? false;

  @override
  void dispose() {
    _disposeRows(_rows);
    super.dispose();
  }

  /// After the frame, once no text field is still using the controllers.
  void _disposeRows(List<_Row>? rows) {
    if (rows == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in rows) {
        row.dispose();
      }
    });
  }

  void _clearRows() {
    _load++;
    _disposeRows(_rows);
    _rows = null;
    _error = null;
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmDiscard() async =>
      !_dirty ||
      await _confirm(
        'Discard unsaved marks?',
        'Marks you typed have not been saved.',
        'Discard',
      );

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _loadClass(Subject subject) async {
    setState(() {
      _subject = subject;
      _clearRows();
    });
    final load = _load;
    try {
      final entries = {
        for (final e in await _repository.forSubject(subject.id)) e.nsin: e,
      };
      final List<StudentRecord> students =
          await StudentRepository().watchAllStudents().first;
      final rows = <_Row>[];
      for (final student in students) {
        final entry = entries.remove(student.nsin);
        final inClass = student.programType == subject.programType &&
            student.year == subject.year &&
            student.semester == subject.semester &&
            student.status == AccountStatus.active;
        // Students with marks stay listed, so a retake or a correction can
        // be entered after they have moved on.
        if (inClass || entry != null) {
          rows.add(_Row(student.nsin, student.name, entry));
        }
      }
      for (final entry in entries.values) {
        rows.add(_Row(entry.nsin, entry.nsin, entry));
      }
      rows.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted || load != _load) {
        for (final row in rows) {
          row.dispose();
        }
        return;
      }
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted || load != _load) return;
      setState(
        () => _error = e is AppFailure
            ? e
            : const CourseworkFailure(
                'Could not load the class. Check your connection and try '
                'again.',
              ),
      );
    }
  }

  CourseworkEntry _entry(_Row row) {
    final saved = row.saved;
    if (saved != null) {
      return saved.copyWith(
        marks: row.marks,
        pendingChanges:
            saved.published && (saved.pendingChanges || row.isChanged),
      );
    }
    final subject = _subject!;
    return CourseworkEntry(
      nsin: row.nsin,
      subjectId: subject.id,
      subjectName: subject.name,
      programType: subject.programType.name,
      year: subject.year,
      semester: subject.semester,
      marks: row.marks,
    );
  }

  bool _allValid() {
    if (_rows!.every((r) => r.isValid)) return true;
    _say('Correct the marks shown in red first.');
    return false;
  }

  /// Runs a write, then records on each row what is now saved.
  Future<void> _write(
    Future<void> Function() write,
    Map<_Row, CourseworkEntry> saved,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      await write();
      if (!mounted) return;
      for (final item in saved.entries) {
        item.key.saved = item.value;
      }
      _say(done);
    } on AppFailure catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDrafts() async {
    if (!_allValid()) return;
    final changed = {
      for (final row in _rows!)
        if (row.isChanged) row: _entry(row),
    };
    if (changed.isEmpty) {
      _say('There is nothing new to save.');
      return;
    }
    await _write(
      () => _repository.saveDrafts(changed.values.toList()),
      changed,
      'Saved. Students do not see unpublished changes.',
    );
  }

  Future<void> _publish() async {
    if (!_allValid()) return;
    final ready = <_Row, CourseworkEntry>{};
    final unfinished = <_Row, CourseworkEntry>{};
    for (final row in _rows!) {
      final saved = row.saved;
      final isNew = saved == null || !saved.published || saved.pendingChanges;
      if (row.marks.isComplete) {
        if (isNew || row.isChanged) {
          ready[row] = _entry(row).copyWith(
            published: true,
            pendingChanges: false,
          );
        }
      } else if (row.isChanged) {
        unfinished[row] = _entry(row);
      }
    }
    if (ready.isEmpty) {
      _say(
        'Nothing to publish. A student needs all five marks, and published '
        'marks must have changed.',
      );
      return;
    }
    final retakes = ready.values.where((e) => e.marks.isRetake).length;
    final confirmed = await _confirm(
      'Publish ${ready.length} result(s)?',
      'Each student will see their own marks.'
          '${retakes > 0 ? ' $retakes marked Retake.' : ''}'
          '${unfinished.isNotEmpty ? ' ${unfinished.length} unfinished will be saved as drafts only.' : ''}',
      'Publish',
    );
    if (!confirmed || !mounted) return;
    await _write(
      () async {
        if (unfinished.isNotEmpty) {
          await _repository.saveDrafts(unfinished.values.toList());
        }
        await _repository.publish(ready.values.toList());
      },
      {...unfinished, ...ready},
      'Published ${ready.length} result(s).',
    );
  }

  Future<void> _recall(List<_Row> rows) async {
    final recalled = {
      for (final row in rows)
        if (row.saved case final saved? when saved.published)
          row: saved.copyWith(published: false, pendingChanges: false),
    };
    if (recalled.isEmpty) {
      _say('Nothing is published.');
      return;
    }
    final confirmed = await _confirm(
      'Recall ${recalled.length} result(s)?',
      'Students will no longer see them. The saved marks are kept.',
      'Recall',
    );
    if (!confirmed || !mounted) return;
    await _write(
      () => _repository.recall(recalled.values.toList()),
      recalled,
      'Recalled ${recalled.length} result(s).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Coursework'),
          actions: [
            if (rows != null && rows.isNotEmpty)
              PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (_) => _recall(rows),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'recall',
                    child: Text('Recall all published'),
                  ),
                ],
              ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 1 + (rows?.length ?? 0),
          itemBuilder: (context, i) =>
              i == 0 ? _buildHeader() : _buildRow(rows![i - 1]),
        ),
        bottomNavigationBar: rows == null || rows.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_dirty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Save your marks to change class.'),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy ? null : _saveDrafts,
                              child: const Text('Save draft'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _busy ? null : _publish,
                              child: const Text('Publish'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      key: const ValueKey('header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Locked while there are unsaved marks, which a change would lose.
        // Dimmed rather than hidden, so that the list does not jump while
        // marks are being typed.
        IgnorePointer(
          ignoring: _dirty || _busy,
          child: Opacity(
            opacity: _dirty ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AcademicStructurePicker(
                  initialTrack: _track,
                  initialYear: _year,
                  initialSemester: _semester,
                  onChanged: (track, year, semester) => setState(() {
                    if (track != _track) {
                      _subjects = track == null
                          ? null
                          : StructureRepository()
                              .watchSubjectsForTrack(track)
                              .first;
                    }
                    _track = track;
                    _year = year;
                    _semester = semester;
                    _subject = null;
                    _clearRows();
                  }),
                ),
                const SizedBox(height: 12),
                if (_year != null && _semester != null) _buildSubjectPicker(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          AppInlineError(failure: _error!),
          OutlinedButton(
            onPressed: () => _loadClass(_subject!),
            child: const Text('Try again'),
          ),
        ] else if (_subject != null && _rows == null)
          const AppLoadingIndicator()
        else if (_rows?.isEmpty ?? false)
          const Text('No active students in this class.'),
      ],
    );
  }

  Widget _buildSubjectPicker() {
    return FutureBuilder<List<Subject>>(
      key: ValueKey(_track),
      future: _subjects,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Could not load the course units.');
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final units = [
          for (final s in snapshot.data!)
            if (s.year == _year && s.semester == _semester) s,
        ]..sort((a, b) => a.name.compareTo(b.name));
        if (units.isEmpty) {
          return const Text(
            'No course units for this class. Add them in Academic Structure.',
          );
        }
        final selected = units.any((s) => s.id == _subject?.id)
            ? _subject!.id
            : null;
        return DropdownButtonFormField<String>(
          key: ValueKey('$_year-$_semester-$selected'),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Course unit'),
          items: [
            for (final unit in units)
              DropdownMenuItem(
                value: unit.id,
                child: Text(unit.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (id) => _loadClass(units.firstWhere((s) => s.id == id)),
        );
      },
    );
  }

  Widget _buildRow(_Row row) {
    final marks = row.marks;
    final saved = row.saved;
    final status = row.isChanged
        ? 'Not saved'
        : saved?.statusLabel ?? 'No marks yet';
    return Card(
      key: ValueKey(row.nsin),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('${row.nsin} · $status'),
                    ],
                  ),
                ),
                if (saved?.published ?? false)
                  IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Recall this result',
                    onPressed: _busy ? null : () => _recall([row]),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final part in kCourseworkParts)
                    SizedBox(
                      // Two fields across on a phone, more on wider screens.
                      width: constraints.maxWidth < 480
                          ? (constraints.maxWidth - 8) / 2
                          : 140,
                      child: TextField(
                        controller: row.fields[part.key],
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '${part.shortLabel} /${part.max}',
                          errorText: row.errorFor(part),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total ${CourseworkMarks.format(marks.total)} / $kCourseworkMax'
              '${marks.isRetake ? ' · Retake' : ''}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: marks.isRetake
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
