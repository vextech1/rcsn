import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/attendance.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/attendance/attendance_list.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// The student's own attendance.
class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  late final Stream<List<Attendance>>? _attendance = _open();

  Stream<List<Attendance>>? _open() {
    final student = context.read<StudentProvider>().currentStudent;
    return student == null ? null : AttendanceRepository().watch(student.nsin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My attendance')),
      body: StreamBuilder<List<Attendance>>(
        stream: _attendance,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const AppErrorDisplay(
              failure: CourseworkFailure(
                'Could not load this. Check your connection and try again.',
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator();
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.event_available,
              title: 'No attendance yet',
              message: 'It appears here when the Registrar records it.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [AttendanceList(items: items)],
          );
        },
      ),
    );
  }
}
