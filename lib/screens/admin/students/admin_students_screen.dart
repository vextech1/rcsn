import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/tutor_account.dart' show AccountStatus;
import '../../../data/repositories/student_repository.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/academic_structure_picker.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Admin's admission-entry screen — Section 5 step 4: a student's record
/// (NSIN, name, Program/Class/Year/Semester) is created here, before the
/// student ever opens the app. Students never self-register (Section
/// 2.3), so this is the ONLY way a StudentRecord comes into existence.
///
/// PATTERN NOTE, consistent with AdminStructureScreen and
/// RoleSelectScreen rather than TutorProvider's dual-purpose design:
/// this screen talks to [StudentRepository] directly rather than through
/// a provider. [StudentProvider] is deliberately scoped to a STUDENT's
/// own NSIN session (see its class doc comment — persistence, the
/// borrowed-phone problem, clearSession) and conflating Admin's
/// admission-entry actions into that class would blur a boundary that
/// was drawn on purpose. This keeps the same unresolved
/// repository-vs-provider convention question flagged on every Admin
/// screen so far — still not a final decision, just consistent with
/// what every other Admin screen currently does.
class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final _repository = StudentRepository();
  final _nsinController = TextEditingController();
  final _nameController = TextEditingController();

  ProgramType? _selectedTrack;
  int? _selectedYear;
  int? _selectedSemester;

  bool _isSubmitting = false;
  AppFailure? _error;

  @override
  void dispose() {
    _nsinController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createStudent() async {
    final nsin = _nsinController.text.trim();
    final name = _nameController.text.trim();

    if (nsin.isEmpty ||
        name.isEmpty ||
        _selectedTrack == null ||
        _selectedYear == null ||
        _selectedSemester == null) {
      setState(() {
        _error = const UnknownFailure(
          'Enter the NSIN, name, and select track, year, and semester.',
        );
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // NSIN format is intentionally NOT validated here beyond basic
      // presence — per the planning conversation, the real course-code
      // segments are still unconfirmed for five of six tracks, and
      // NsinValidator's shape-check is deliberately permissive. Admin
      // entering a real school-issued NSIN should never be rejected by
      // an incomplete validator; createStudentRecord's own duplicate
      // check is the meaningful guard at this step.
      await _repository.createStudentRecord(
        nsin: nsin,
        name: name,
        programType: _selectedTrack!,
        year: _selectedYear!,
        semester: _selectedSemester!,
      );
      _nsinController.clear();
      _nameController.clear();
    } on AppFailure catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _changeStatus(StudentRecord student, AccountStatus status) async {
    if (status == AccountStatus.terminated) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Terminate course?'),
          content: Text(
            '${student.name} will no longer be able to access their '
            'academic data. This can be reversed later.',
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
    }

    try {
      await _repository.updateStudentStatus(
        studentId: student.id,
        status: status,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
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
                      'Register a Student (Admission)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _nsinController,
                      label: 'NSIN',
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _nameController,
                      label: 'Full Name',
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
                    if (_error != null) AppInlineError(failure: _error!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _createStudent,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Register Student'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildStudentList()),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    return StreamBuilder<List<StudentRecord>>(
      stream: _repository.watchAllStudents(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingIndicator();
        }
        if (snapshot.hasError) {
          return AppErrorDisplay(
            failure: UnknownFailure(snapshot.error.toString()),
          );
        }

        final students = snapshot.data ?? [];
        if (students.isEmpty) {
          return const AppEmptyState(
            icon: Icons.badge_outlined,
            title: 'No students registered yet',
            message: 'Students entered at admission will appear here.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: students.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final student = students[index];
            return ListTile(
              title: Text(student.name),
              subtitle: Text(
                '${student.nsin} · Year ${student.year}, Sem ${student.semester} '
                '· ${_statusLabel(student.status)}',
              ),
              trailing: PopupMenuButton<AccountStatus>(
                onSelected: (status) => _changeStatus(student, status),
                itemBuilder: (context) => [
                  if (student.status != AccountStatus.active)
                    const PopupMenuItem(
                      value: AccountStatus.active,
                      child: Text('Reactivate'),
                    ),
                  if (student.status != AccountStatus.suspended)
                    const PopupMenuItem(
                      value: AccountStatus.suspended,
                      child: Text('Suspend'),
                    ),
                  if (student.status != AccountStatus.terminated)
                    const PopupMenuItem(
                      value: AccountStatus.terminated,
                      child: Text('Terminate course'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _statusLabel(AccountStatus status) {
    switch (status) {
      case AccountStatus.active:
        return 'Active';
      case AccountStatus.suspended:
        return 'Suspended';
      case AccountStatus.terminated:
        return 'Terminated';
    }
  }
}
