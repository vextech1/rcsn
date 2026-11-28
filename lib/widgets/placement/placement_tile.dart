import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/placement.dart';
import '../../data/repositories/placement_repository.dart';

/// The student dashboard's way to clinical placements, shown only when there
/// is one.
class PlacementTile extends StatefulWidget {
  final String nsin;
  const PlacementTile({super.key, required this.nsin});

  @override
  State<PlacementTile> createState() => _PlacementTileState();
}

class _PlacementTileState extends State<PlacementTile> {
  late final _placements = PlacementRepository().watch(widget.nsin);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Placement>>(
      stream: _placements,
      builder: (context, snapshot) {
        if (snapshot.data?.isEmpty ?? true) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.local_hospital, color: AppColors.primary),
          title: const Text('My clinical placements'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.studentPlacements),
        );
      },
    );
  }
}
