import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/discipline_case.dart';
import '../../data/repositories/discipline_repository.dart';

/// The student dashboard's way to disciplinary cases, shown only when there
/// is one to see.
class DisciplineTile extends StatefulWidget {
  final String nsin;
  const DisciplineTile({super.key, required this.nsin});

  @override
  State<DisciplineTile> createState() => _DisciplineTileState();
}

class _DisciplineTileState extends State<DisciplineTile> {
  late final _cases = DisciplineRepository().watchVisible(widget.nsin);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DisciplineCase>>(
      stream: _cases,
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.gavel, color: AppColors.primary),
          title: Text('My disciplinary cases ($count)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.studentDiscipline),
        );
      },
    );
  }
}
