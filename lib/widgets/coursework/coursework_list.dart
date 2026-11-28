import 'package:flutter/material.dart';
import '../../data/models/coursework.dart';

/// Coursework results grouped by class, read-only. [entries] must already be
/// in class order.
class CourseworkList extends StatelessWidget {
  final List<CourseworkEntry> entries;

  /// Staff also see whether each result is a draft or published.
  final bool showStatus;

  const CourseworkList({
    super.key,
    required this.entries,
    this.showStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? heading;
    for (final entry in entries) {
      final next = 'Year ${entry.year}, Semester ${entry.semester}';
      if (next != heading) {
        heading = next;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(next, style: Theme.of(context).textTheme.labelLarge),
          ),
        );
      }
      children.add(_card(context, entry));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _card(BuildContext context, CourseworkEntry entry) {
    final marks = entry.marks;
    final error = Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.subjectName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (showStatus) Text(entry.statusLabel),
            const SizedBox(height: 8),
            for (final part in kCourseworkParts)
              Row(
                children: [
                  Expanded(child: Text(part.label)),
                  Text(
                    marks.values[part.key] == null
                        ? '-'
                        : '${CourseworkMarks.format(marks.values[part.key]!)}'
                            ' / ${part.max}',
                  ),
                ],
              ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    marks.isComplete ? 'Total' : 'Total so far',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${CourseworkMarks.format(marks.total)} / $kCourseworkMax',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (marks.isRetake)
              Text(
                'Retake',
                style: TextStyle(color: error, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}
