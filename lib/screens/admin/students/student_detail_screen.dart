import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/student_number.dart';
import '../../../data/models/coursework.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/subject.dart';
import '../../../data/models/timetable.dart';
import '../../../data/repositories/coursework_repository.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../data/repositories/student_bio_repository.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../data/repositories/tutor_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/coursework/coursework_list.dart';

/// Everything on record about one student, read-only.
///
/// Tuition is shown only to the Principal and Deputy Principal: the rules do
/// not let the Registrar read fee records.
class StudentDetailScreen extends StatefulWidget {
  final StudentRecord student;
  const StudentDetailScreen({super.key, required this.student});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late final bool _showFees =
      context.read<AuthProvider>().resolvedRole?.isPrincipalLevel ?? false;
  late Future<Map<String, String>> _bio = _loadBio();
  late final _subjects = _loadSubjects();
  late final _timetables = _loadTimetables();
  late final _coursework = CourseworkRepository().forStudent(_student.nsin);
  late final _fees =
      _showFees ? FeeRepository().recordsForStudent(_student.nsin) : null;

  StudentRecord get _student => widget.student;
  String get _bioKey => StudentNumber.bioKey(_student.nsin);

  Future<Map<String, String>> _loadBio() =>
      StudentBioRepository().load(_bioKey);

  /// The subjects of the student's class, each with its tutors' names.
  Future<List<(Subject, String)>> _loadSubjects() async {
    final all = await StructureRepository()
        .watchSubjectsForTrack(_student.programType)
        .first;
    final tutors = TutorRepository();
    final names = {
      for (final t in await tutors.watchAllTutors().first) t.id: t.name,
    };
    final result = <(Subject, String)>[];
    for (final subject in all) {
      if (subject.year != _student.year ||
          subject.semester != _student.semester) {
        continue;
      }
      final assigned = await tutors.tutorIdsFor(subject.id);
      result.add((
        subject,
        assigned.map((id) => names[id]).whereType<String>().join(', '),
      ));
    }
    return result;
  }

  /// Timetables that apply to the student's class, drafts included.
  Future<List<Timetable>> _loadTimetables() async {
    final all = await TimetableRepository().fetchAll();
    return [
      for (final t in all)
        if ((t.programType.isEmpty ||
                t.programType == _student.programType.name) &&
            (t.year == 0 || t.year == _student.year) &&
            (t.semester == 0 || t.semester == _student.semester))
          t,
    ];
  }

  Future<void> _editBio() async {
    await context.push(
      AppRoutes.registrarStudentBio,
      extra: (bioKey: _bioKey, label: '${_student.name} · ${_student.nsin}'),
    );
    if (mounted) setState(() => _bio = _loadBio());
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label)),
            Expanded(
              child: Text(
                value.isEmpty ? 'Not recorded' : value,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

  /// One section's loading, failure and content, so that one failure does
  /// not hide the rest.
  Widget _section<T>(Future<T> future, List<Widget> Function(T) build) =>
      FutureBuilder<T>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Could not load this. Open the student again.');
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: build(snapshot.data as T),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final status = _student.status.name;
    return Scaffold(
      appBar: AppBar(title: const Text('Student')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_student.name, style: Theme.of(context).textTheme.headlineSmall),
          _heading('Admission'),
          _row('Student number', _student.nsin),
          _row(
            'Programme',
            kTrackDefinitions[_student.programType]?.label ??
                _student.programType.name,
          ),
          _row('Class', 'Year ${_student.year}, Semester ${_student.semester}'),
          _row('Status', status[0].toUpperCase() + status.substring(1)),
          _row('Admitted', DateFormat('d MMM y').format(_student.admittedAt)),
          _heading('Bio data'),
          _section<Map<String, String>>(
            _bio,
            (bio) => [
              _row('Date of birth', bio['dateOfBirth'] ?? ''),
              _row('Home district', bio['district'] ?? ''),
              _row('Village', bio['village'] ?? ''),
              _row('Primary school', bio['primarySchool'] ?? ''),
              _row('Secondary school', bio['secondarySchool'] ?? ''),
              OutlinedButton.icon(
                onPressed: _editBio,
                icon: const Icon(Icons.edit),
                label: const Text('Edit bio data'),
              ),
            ],
          ),
          _heading('Subjects this semester'),
          _section<List<(Subject, String)>>(
            _subjects,
            (subjects) => [
              if (subjects.isEmpty) const Text('No subjects set up.'),
              for (final (subject, tutors) in subjects)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(subject.name),
                  subtitle: Text(
                    tutors.isEmpty ? 'No tutor assigned' : 'Tutor: $tutors',
                  ),
                ),
            ],
          ),
          _heading('Coursework'),
          _section<List<CourseworkEntry>>(
            _coursework,
            (entries) => [
              if (entries.isEmpty)
                const Text('No coursework recorded.')
              else
                CourseworkList(entries: entries, showStatus: true),
            ],
          ),
          _heading('Timetables'),
          _section<List<Timetable>>(
            _timetables,
            (timetables) => [
              if (timetables.isEmpty) const Text('No timetables for this class.'),
              for (final t in timetables)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(t.type.icon),
                  title: Text(t.title),
                  subtitle: Text(
                    t.isPublished ? t.type.label : '${t.type.label} · Draft',
                  ),
                  onTap: () => context.push(AppRoutes.timetableView(t.id)),
                ),
            ],
          ),
          if (_fees case final fees?) ...[
            _heading('Tuition'),
            _section(
              fees,
              (records) => [
                if (records.isEmpty) const Text('No fee records.'),
                for (final fee in records)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Year ${fee.year}, Semester ${fee.semester}'),
                    subtitle: Text(
                      'Paid ${formatUgx(fee.paid)} of ${formatUgx(fee.tuition)}'
                      ' · ${fee.status.label}',
                    ),
                    onTap: () => context.push(
                      AppRoutes.principalFeeRecord,
                      extra: fee.id,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
