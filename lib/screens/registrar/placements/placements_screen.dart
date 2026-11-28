import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/placement.dart';
import '../../../data/models/student_record.dart';
import '../../../data/repositories/placement_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/date_field.dart';
import '../../../widgets/placement/placement_card.dart';

/// One student's clinical placements. The Registrar edits them; the Principal
/// and Deputy only look.
class PlacementsScreen extends StatefulWidget {
  final StudentRecord student;
  const PlacementsScreen({super.key, required this.student});

  @override
  State<PlacementsScreen> createState() => _PlacementsScreenState();
}

class _PlacementsScreenState extends State<PlacementsScreen> {
  final _repository = PlacementRepository();
  late final _placements = _repository.watch(_nsin);
  late final bool _canEdit =
      context.read<AuthProvider>().resolvedRole == UserRole.registrar;

  String get _nsin => widget.student.nsin;

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// The dialog saves, so that nothing typed is lost if saving fails.
  Future<void> _edit([Placement? placement]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlacementDialog(
        repository: _repository,
        nsin: _nsin,
        placement: placement,
      ),
    );
    if (saved == true && mounted) _say('Placement saved.');
  }

  Future<void> _delete(Placement placement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this placement?'),
        content: Text(placement.hospital),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.delete(_nsin, placement.id);
    } on AppFailure catch (e) {
      if (mounted) _say(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clinical placements')),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Add placement'),
            )
          : null,
      body: StreamBuilder<List<Placement>>(
        stream: _placements,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const AppErrorDisplay(
              failure: CourseworkFailure(
                'Could not load the placements. Check your connection and '
                'permissions.',
              ),
            );
          }
          final placements = snapshot.data;
          if (placements == null) return const AppLoadingIndicator();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              Text(
                '${widget.student.name} · $_nsin',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (placements.isEmpty) const Text('No placements recorded.'),
              for (final p in placements)
                PlacementCard(
                  placement: p,
                  menu: _canEdit
                      ? PopupMenuButton<String>(
                          onSelected: (choice) =>
                              choice == 'edit' ? _edit(p) : _delete(p),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Change')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PlacementDialog extends StatefulWidget {
  final PlacementRepository repository;
  final String nsin;

  /// The placement being changed, or null for a new one.
  final Placement? placement;

  const _PlacementDialog({
    required this.repository,
    required this.nsin,
    required this.placement,
  });

  @override
  State<_PlacementDialog> createState() => _PlacementDialogState();
}

class _PlacementDialogState extends State<_PlacementDialog> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.placement?.id ?? widget.repository.newId();
  late final _hospital =
      TextEditingController(text: widget.placement?.hospital);
  late final _activities =
      TextEditingController(text: widget.placement?.activities);
  late final _experience =
      TextEditingController(text: widget.placement?.experience);
  late final _start = TextEditingController(text: widget.placement?.startDate);
  late final _end = TextEditingController(text: widget.placement?.endDate);
  bool _busy = false;
  AppFailure? _error;

  @override
  void dispose() {
    for (final c in [_hospital, _activities, _experience, _start, _end]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final dates = Placement.dateError(_start.text, _end.text);
    if (dates != null) {
      setState(() => _error = CourseworkFailure(dates));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        widget.nsin,
        Placement(
          id: _id,
          hospital: _hospital.text.trim(),
          activities: _activities.text.trim(),
          experience: _experience.text.trim(),
          startDate: _start.text,
          endDate: _end.text,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Widget _text(
    TextEditingController controller,
    String label,
    String missing,
  ) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        textCapitalization: TextCapitalization.sentences,
        maxLength: Placement.maxText,
        minLines: 3,
        maxLines: 8,
        validator: (v) => (v ?? '').trim().isEmpty ? missing : null,
      );

  Widget _dateField(TextEditingController controller, String label) {
    final now = DateTime.now();
    return DateField(
      controller: controller,
      label: label,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.placement == null ? 'Add placement' : 'Change placement',
      ),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _hospital,
              decoration: const InputDecoration(labelText: 'Hospital'),
              textCapitalization: TextCapitalization.words,
              maxLength: Placement.maxHospital,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the hospital' : null,
            ),
            _dateField(_start, 'Start date'),
            const SizedBox(height: 12),
            _dateField(_end, 'End date'),
            const SizedBox(height: 12),
            _text(
              _activities,
              'Activities to perform',
              'Enter the activities',
            ),
            _text(
              _experience,
              'Experience to gain',
              'Enter the experience to gain',
            ),
            if (_error != null) AppInlineError(failure: _error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
