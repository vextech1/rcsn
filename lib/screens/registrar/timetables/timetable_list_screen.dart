import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/timetable.dart';
import '../../../data/models/timetable_templates.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../public/public_post_widgets.dart';

/// Who is looking at the list, which decides what is listed and what can
/// be done.
enum TimetableListMode {
  /// Registrar: everything incl. drafts; create, publish, duplicate, delete.
  registrar,

  /// Principal: everything incl. drafts, view only.
  principal,

  /// A student: published for students and the public, narrowed to the
  /// student's own program, year and semester.
  student,

  /// Tutors and staff: all published.
  staff,

  /// Anyone, no sign-in: published and marked public.
  everyone,
}

/// "Certificate – Nursing · Year 1 · Sem 2", or '' when it applies to all.
String trackText(Timetable t) {
  final parts = <String>[];
  if (t.programType.isNotEmpty) {
    String? label;
    for (final p in ProgramType.values) {
      if (p.name == t.programType) label = kTrackDefinitions[p]?.label;
    }
    parts.add(label ?? t.programType);
  }
  if (t.year > 0) parts.add('Year ${t.year}');
  if (t.semester > 0) parts.add('Sem ${t.semester}');
  return parts.join(' · ');
}

bool _matchesStudent(Timetable t, StudentRecord s) =>
    (t.programType.isEmpty || t.programType == s.programType.name) &&
    (t.year == 0 || t.year == s.year) &&
    (t.semester == 0 || t.semester == s.semester);

String _modeTitle(TimetableListMode mode) {
  switch (mode) {
    case TimetableListMode.registrar:
    case TimetableListMode.principal:
      return 'Timetables and calendars';
    case TimetableListMode.student:
    case TimetableListMode.staff:
    case TimetableListMode.everyone:
      return 'Timetables';
  }
}

class TimetableListScreen extends StatelessWidget {
  final TimetableListMode mode;

  const TimetableListScreen({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_modeTitle(mode))),
      body: TimetableListBody(mode: mode),
    );
  }
}

/// The list without a Scaffold, so the Public Space can embed it as a tab.
class TimetableListBody extends StatefulWidget {
  final TimetableListMode mode;

  const TimetableListBody({super.key, required this.mode});

  @override
  State<TimetableListBody> createState() => _TimetableListBodyState();
}

class _TimetableListBodyState extends State<TimetableListBody>
    with AutomaticKeepAliveClientMixin {
  final _repository = TimetableRepository();
  late Future<List<Timetable>> _future;
  String? _busyId;

  @override
  bool get wantKeepAlive => true;

  bool get _canEdit => widget.mode == TimetableListMode.registrar;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Timetable>> _load() async {
    switch (widget.mode) {
      case TimetableListMode.registrar:
      case TimetableListMode.principal:
        return _repository.fetchAll();
      case TimetableListMode.student:
        final all = await _repository.fetchPublished(
          audiences: const [
            TimetableAudience.students,
            TimetableAudience.everyone,
          ],
        );
        final student = context.read<StudentProvider>().currentStudent;
        return student == null
            ? all
            : all.where((t) => _matchesStudent(t, student)).toList();
      case TimetableListMode.staff:
        return _repository.fetchPublished(
          audiences: TimetableAudience.values,
        );
      case TimetableListMode.everyone:
        return _repository.fetchPublished(
          audiences: const [TimetableAudience.everyone],
        );
    }
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Timetable t) async {
    if (_canEdit) {
      await context.push(AppRoutes.registrarTimetableEdit(t.id));
      if (mounted) _refresh();
    } else {
      await context.push(AppRoutes.timetableView(t.id));
    }
  }

  Future<void> _create() async {
    final template = await showModalBottomSheet<TimetableTemplate>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Start from a template',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final t in TimetableTemplate.values)
              ListTile(
                leading: Icon(t.icon, color: AppColors.primary),
                title: Text(t.label),
                subtitle: Text(t.description),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      ),
    );
    if (template == null || !mounted) return;

    try {
      final id = await _repository.create(buildTemplate(template));
      if (!mounted) return;
      await context.push(AppRoutes.registrarTimetableEdit(id));
      if (mounted) _refresh();
    } on AppFailure catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _duplicate(Timetable t) async {
    setState(() => _busyId = t.id);
    try {
      final full = await _repository.get(t.id);
      if (full != null) {
        await _repository.create(full.copyWith(title: 'Copy of ${full.title}'));
        _snack('Duplicated as a draft.');
        await _refresh();
      }
    } on AppFailure catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _togglePublish(Timetable t) async {
    setState(() => _busyId = t.id);
    try {
      await _repository.setStatus(
        t.id,
        t.isPublished ? TimetableStatus.draft : TimetableStatus.published,
      );
      _snack(t.isPublished ? 'Unpublished.' : 'Published.');
      await _refresh();
    } on AppFailure catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(Timetable t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${t.title}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyId = t.id);
    try {
      await _repository.delete(t.id);
      _snack('Deleted.');
      await _refresh();
    } on AppFailure catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final list = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Timetable>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoadingIndicator();
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                AppErrorDisplay(
                  failure: UnknownFailure(snapshot.error.toString()),
                  onRetry: _refresh,
                ),
              ],
            );
          }

          final items = snapshot.data ?? const <Timetable>[];
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                AppEmptyState(
                  icon: Icons.calendar_month,
                  title: 'No timetables yet',
                  message: _canEdit
                      ? 'Tap "New" to build the first one from a template.'
                      : 'Nothing has been published here yet. Check back soon.',
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _tile(items[i]),
          );
        },
      ),
    );

    if (!_canEdit) return list;

    return Stack(
      children: [
        Positioned.fill(child: list),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('New'),
          ),
        ),
      ],
    );
  }

  Widget _tile(Timetable t) {
    final showStatus = widget.mode == TimetableListMode.registrar ||
        widget.mode == TimetableListMode.principal;
    final track = trackText(t);
    final subtitle = [
      t.type.label,
      if (t.academicYear.isNotEmpty) t.academicYear,
      if (track.isNotEmpty) track,
      if (t.updatedAt != null) 'Updated ${formatPostDate(t.updatedAt)}',
    ].join(' · ');

    final Widget trailing;
    if (_busyId == t.id) {
      trailing = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_canEdit) {
      trailing = PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              _open(t);
            case 'duplicate':
              _duplicate(t);
            case 'publish':
              _togglePublish(t);
            case 'delete':
              _delete(t);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Open and edit')),
          PopupMenuItem(
            value: 'publish',
            child: Text(t.isPublished ? 'Unpublish' : 'Publish'),
          ),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    } else {
      trailing = const Icon(Icons.chevron_right);
    }

    return ListTile(
      leading: Icon(t.type.icon, color: AppColors.primary),
      title: Text(t.title),
      subtitle: Text(subtitle),
      isThreeLine: subtitle.length > 48,
      onTap: () => _open(t),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStatus)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                t.isPublished ? 'Published' : 'Draft',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.isPublished ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
          trailing,
        ],
      ),
    );
  }
}
