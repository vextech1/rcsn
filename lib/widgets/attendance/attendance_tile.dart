import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/attendance.dart';
import '../../data/repositories/attendance_repository.dart';

/// The student dashboard's way to attendance, shown once some is recorded.
class AttendanceTile extends StatefulWidget {
  final String nsin;
  const AttendanceTile({super.key, required this.nsin});

  @override
  State<AttendanceTile> createState() => _AttendanceTileState();
}

class _AttendanceTileState extends State<AttendanceTile> {
  late final _attendance = AttendanceRepository().watch(widget.nsin);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Attendance>>(
      stream: _attendance,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const SizedBox.shrink();
        final low = items.where((a) => a.isLow).length;
        return ListTile(
          leading: const Icon(Icons.event_available, color: AppColors.primary),
          title: const Text('My attendance'),
          subtitle: low == 0
              ? null
              : Text(
                  '$low course unit(s) below ${kAttendanceMinimum.toInt()}%',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.studentAttendance),
        );
      },
    );
  }
}
