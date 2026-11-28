import 'package:flutter/material.dart';
import '../../data/models/attendance.dart';

/// Attendance per course unit, read-only. [items] must already be in class
/// order.
class AttendanceList extends StatelessWidget {
  final List<Attendance> items;
  const AttendanceList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Card(
            child: ListTile(
              title: Text(item.subjectName),
              subtitle: Text(
                'Year ${item.year}, Semester ${item.semester}'
                '${item.isLow ? '\nBelow ${kAttendanceMinimum.toInt()}%' : ''}',
                style: item.isLow ? TextStyle(color: error) : null,
              ),
              trailing: Text(
                '${item.percentText}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: item.isLow ? error : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
