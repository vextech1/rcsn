import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/timetable.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../public/public_post_widgets.dart';
import 'timetable_grid.dart';
import 'timetable_list_screen.dart' show trackText;

/// Read-only view of one timetable, for everyone: students, tutors, the
/// public, the Principal (who can also see drafts) and the Registrar.
class TimetableViewerScreen extends StatefulWidget {
  final String timetableId;

  const TimetableViewerScreen({super.key, required this.timetableId});

  @override
  State<TimetableViewerScreen> createState() => _TimetableViewerScreenState();
}

class _TimetableViewerScreenState extends State<TimetableViewerScreen> {
  final _repository = TimetableRepository();
  late Future<Timetable?> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.get(widget.timetableId);
  }

  void _reload() {
    setState(() => _future = _repository.get(widget.timetableId));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Timetable?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Timetable')),
            body: const AppLoadingIndicator(),
          );
        }
        if (snapshot.hasError) {
          // A draft read by someone who may not see it also lands here.
          return Scaffold(
            appBar: AppBar(title: const Text('Timetable')),
            body: AppErrorDisplay(
              failure: const UnknownFailure(
                'This timetable is not available. It may not be published yet.',
              ),
              onRetry: _reload,
            ),
          );
        }
        final timetable = snapshot.data;
        if (timetable == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Timetable')),
            body: AppErrorDisplay(
              failure: const UnknownFailure('This timetable no longer exists.'),
              onRetry: _reload,
            ),
          );
        }
        return _Loaded(timetable: timetable);
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  final Timetable timetable;

  const _Loaded({required this.timetable});

  @override
  Widget build(BuildContext context) {
    final track = trackText(timetable);
    final meta = [
      if (timetable.academicYear.isNotEmpty) timetable.academicYear,
      if (track.isNotEmpty) track,
      if (timetable.updatedAt != null)
        'Updated ${formatPostDate(timetable.updatedAt)}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(timetable.type.label)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(timetable.title, style: AppTypography.heading2(context)),
                if (timetable.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(timetable.subtitle,
                      style: AppTypography.bodyMuted(context)),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, style: AppTypography.caption(context)),
                ],
                if (!timetable.isPublished) ...[
                  const SizedBox(height: 8),
                  const Chip(label: Text('Draft: not yet published')),
                ],
              ],
            ),
          ),
          Expanded(child: TimetableGrid(timetable: timetable)),
          if (timetable.footnotes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final note in timetable.footnotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(note, style: AppTypography.caption(context)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
