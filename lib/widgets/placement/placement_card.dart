import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/placement.dart';

/// One clinical placement. [menu] holds the Registrar's actions.
class PlacementCard extends StatelessWidget {
  final Placement placement;
  final Widget? menu;

  const PlacementCard({super.key, required this.placement, this.menu});

  static String _date(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : DateFormat('d MMM y').format(date);
  }

  Widget _part(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value.isEmpty ? 'Not recorded' : value),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    placement.hospital,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (menu != null) menu!,
              ],
            ),
            Text(
              '${_date(placement.startDate)} to ${_date(placement.endDate)}'
              ' · ${placement.stage(DateTime.now())}',
            ),
            _part('Activities to perform', placement.activities),
            _part('Experience to gain', placement.experience),
          ],
        ),
      ),
    );
  }
}
