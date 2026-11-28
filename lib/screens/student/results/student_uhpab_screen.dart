import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/uhpab.dart';
import '../../../data/services/uhpab_service.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/coursework/open_result_document.dart';

/// The student's published UHPAB results. Asked for afresh each time, so a
/// payment or a recall shows at once.
class StudentUhpabScreen extends StatefulWidget {
  const StudentUhpabScreen({super.key});

  @override
  State<StudentUhpabScreen> createState() => _StudentUhpabScreenState();
}

class _StudentUhpabScreenState extends State<StudentUhpabScreen> {
  late final String? _nsin =
      context.read<StudentProvider>().currentStudent?.nsin;
  late Future<UhpabResults>? _results = _load();

  Future<UhpabResults>? _load() {
    final nsin = _nsin;
    return nsin == null ? null : UhpabService().forStudent(nsin);
  }

  void _reload() => setState(() => _results = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My UHPAB results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<UhpabResults>(
        future: _results,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator();
          }
          final error = snapshot.error;
          if (error != null) {
            return AppErrorDisplay(
              failure: error is AppFailure
                  ? error
                  : const CourseworkFailure('Could not load your results.'),
            );
          }
          final results = snapshot.data;
          if (results != null && results.blocked) {
            return const AppEmptyState(
              icon: Icons.lock_outline,
              title: 'Results held',
              message: 'Your UHPAB results are held because your fees are not '
                  'cleared. See the Bursar.',
            );
          }
          if (results == null || results.isEmpty) {
            return const AppEmptyState(
              icon: Icons.workspace_premium,
              title: 'No results yet',
              message: 'Results appear here when the Registrar publishes them.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final unit in results.units)
                Card(
                  child: ListTile(
                    title: Text(unit.subjectName),
                    subtitle: Text(
                      'Year ${unit.year}, Semester ${unit.semester}\n'
                      '${unit.summary}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              for (final document in results.documents)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(document.title),
                    trailing: const Icon(Icons.download),
                    onTap: () => openResultDocument(
                      context,
                      _nsin!,
                      document,
                      studentNsin: _nsin,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
