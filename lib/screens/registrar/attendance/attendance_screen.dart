import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/attendance.dart';
import '../../../data/models/subject.dart';
import '../../../data/models/tutor_account.dart' show AccountStatus;
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../data/repositories/student_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/academic_structure_picker.dart';

/// The Registrar enters one course unit's attendance for a class. Students see
/// it once saved.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

/// One student on the class list.
class _Row {
  final String nsin;
  final String name;

  /// What is in the database, null if nothing has been recorded.
  Attendance? saved;

  final TextEditingController field;

  _Row(this.nsin, this.name, this.saved)
      : field = TextEditingController(text: saved?.percentText ?? '');

  String? get error => Attendance.errorFor(field.text);

  double? get percent => error != null || field.text.trim().isEmpty
      ? null
      : double.parse(field.text.trim());

  bool get isChanged => error != null || percent != saved?.percent;
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _repository = AttendanceRepository();

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
        row.field.dispose();
      }
    });
  }

  void _clearRows() {
    _load++;
    _disposeRows(_rows);
    _rows = null;
    _error = null;
  }

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
      final recorded = await _repository.forSubject(subject.id);
      final students = await StudentRepository().watchAllStudents().first;
      if (!mounted || load != _load) return;
      final rows = <_Row>[];
      for (final student in students) {
        final saved = recorded.remove(student.nsin);
        final inClass = student.programType == subject.programType &&
            student.year == subject.year &&
            student.semester == subject.semester &&
            student.status == AccountStatus.active;
        // Students with a record stay listed, so it can be corrected.
        if (inClass || saved != null) {
          rows.add(_Row(student.nsin, student.name, saved));
        }
      }
      for (final entry in recorded.entries) {
        rows.add(_Row(entry.key, entry.key, entry.value));
      }
      rows.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
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

  Future<void> _save() async {
    final rows = _rows!;
    if (rows.any((r) => r.error != null)) {
      _say('Correct the values shown in red first.');
      return;
    }
    final subject = _subject!;
    final changed = {
      for (final row in rows)
        if (row.isChanged)
          row: row.percent == null
              ? null
              : Attendance(
                  subjectId: subject.id,
                  subjectName: subject.name,
                  year: subject.year,
                  semester: subject.semester,
                  percent: row.percent!,
                ),
    };
    if (changed.isEmpty) {
      _say('There is nothing new to save.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.save(subject.id, {
        for (final entry in changed.entries) entry.key.nsin: entry.value,
      });
      if (!mounted) return;
      for (final entry in changed.entries) {
        entry.key.saved = entry.value;
      }
      _say('Saved.');
    } on AppFailure catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardAndLeave() async {
    final navigator = Navigator.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved attendance?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _discardAndLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Attendance')),
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
                  child: ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: Text(
                      _dirty ? 'Save (needed to change class)' : 'Save',
                    ),
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
        // Locked while there are unsaved values, which a change would lose.
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
          onChanged: (id) => _loadClass(units.firstWhere((s) => s.id == id)),
        );
      },
    );
  }

  Widget _buildRow(_Row row) {
    final percent = row.percent;
    final low = percent != null && percent < kAttendanceMinimum;
    return Padding(
      key: ValueKey(row.nsin),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('${row.nsin}${row.isChanged ? ' · Not saved' : ''}'),
                if (low)
                  Text(
                    'Below ${kAttendanceMinimum.toInt()}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: TextField(
              controller: row.field,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Percent',
                suffixText: '%',
                errorText: row.error,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
