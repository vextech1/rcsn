import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/placement.dart';
import '../../../data/repositories/placement_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/placement/placement_card.dart';

/// The student's own clinical placements.
class StudentPlacementsScreen extends StatefulWidget {
  const StudentPlacementsScreen({super.key});

  @override
  State<StudentPlacementsScreen> createState() =>
      _StudentPlacementsScreenState();
}

class _StudentPlacementsScreenState extends State<StudentPlacementsScreen> {
  late final Stream<List<Placement>>? _placements = _open();

  Stream<List<Placement>>? _open() {
    final student = context.read<StudentProvider>().currentStudent;
    return student == null ? null : PlacementRepository().watch(student.nsin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My clinical placements')),
      body: StreamBuilder<List<Placement>>(
        stream: _placements,
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
          final placements = snapshot.data ?? [];
          if (placements.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_hospital,
              title: 'No placements yet',
              message: 'Your placement appears here when the Registrar adds it.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final p in placements) PlacementCard(placement: p),
            ],
          );
        },
      ),
    );
  }
}
