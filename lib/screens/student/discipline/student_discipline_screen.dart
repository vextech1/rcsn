import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/discipline_case.dart';
import '../../../data/repositories/discipline_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/discipline/case_card.dart';

/// The cases the school has made visible to the student.
class StudentDisciplineScreen extends StatefulWidget {
  const StudentDisciplineScreen({super.key});

  @override
  State<StudentDisciplineScreen> createState() =>
      _StudentDisciplineScreenState();
}

class _StudentDisciplineScreenState extends State<StudentDisciplineScreen> {
  late final Stream<List<DisciplineCase>>? _cases = _open();

  Stream<List<DisciplineCase>>? _open() {
    final student = context.read<StudentProvider>().currentStudent;
    return student == null
        ? null
        : DisciplineRepository().watchVisible(student.nsin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My disciplinary cases')),
      body: StreamBuilder<List<DisciplineCase>>(
        stream: _cases,
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
          final cases = snapshot.data ?? [];
          if (cases.isEmpty) {
            return const AppEmptyState(
              icon: Icons.gavel,
              title: 'No cases',
              message: 'There is nothing to show.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final item in cases) CaseCard(item: item)],
          );
        },
      ),
    );
  }
}
