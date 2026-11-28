import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/coursework.dart';
import '../../../data/repositories/coursework_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/coursework/coursework_list.dart';

/// The student's published coursework. Live, so a recalled result
/// disappears.
class StudentResultsScreen extends StatefulWidget {
  const StudentResultsScreen({super.key});

  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  late final Stream<List<CourseworkEntry>>? _results = _open();

  Stream<List<CourseworkEntry>>? _open() {
    final student = context.read<StudentProvider>().currentStudent;
    return student == null
        ? null
        : CourseworkRepository().watchPublished(student.nsin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My coursework results')),
      body: StreamBuilder<List<CourseworkEntry>>(
        stream: _results,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const AppErrorDisplay(
              failure: CourseworkFailure(
                'Could not load your results. Check your connection and try '
                'again.',
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator();
          }
          final entries = snapshot.data ?? [];
          if (entries.isEmpty) {
            return const AppEmptyState(
              icon: Icons.grading,
              title: 'No results yet',
              message: 'Results appear here when the Registrar publishes them.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [CourseworkList(entries: entries)],
          );
        },
      ),
    );
  }
}
