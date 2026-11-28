import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/discipline_case.dart';

/// One disciplinary case.
class CaseCard extends StatelessWidget {
  final DisciplineCase item;

  /// Staff also see whether the student can see it, and can tap to change it.
  final bool staff;
  final VoidCallback? onTap;

  const CaseCard({
    super.key,
    required this.item,
    this.staff = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(item.date);
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(item.offence),
        subtitle: Text(
          [
            '${date == null ? item.date : DateFormat('d MMM y').format(date)}'
                ' · ${item.status.label}',
            'Action: ${item.action.isEmpty ? 'None recorded' : item.action}',
            if (staff)
              item.visible
                  ? 'Visible to the student'
                  : 'Hidden from the student',
          ].join('\n'),
        ),
        trailing: onTap == null ? null : const Icon(Icons.edit),
      ),
    );
  }
}
