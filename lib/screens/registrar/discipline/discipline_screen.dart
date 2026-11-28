import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/discipline_case.dart';
import '../../../data/models/student_record.dart';
import '../../../data/repositories/discipline_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/discipline/case_card.dart';
import '../../../widgets/forms/date_field.dart';

/// One student's disciplinary cases, recorded by the Registrar, Principal or
/// Deputy Principal.
class DisciplineScreen extends StatefulWidget {
  final StudentRecord student;
  const DisciplineScreen({super.key, required this.student});

  @override
  State<DisciplineScreen> createState() => _DisciplineScreenState();
}

class _DisciplineScreenState extends State<DisciplineScreen> {
  final _repository = DisciplineRepository();
  late final _cases = _repository.watch(widget.student.nsin);

  /// The dialog saves, so that nothing typed is lost if saving fails.
  Future<void> _edit([DisciplineCase? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CaseDialog(
        repository: _repository,
        nsin: widget.student.nsin,
        item: item,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Case saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Disciplinary cases')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Record a case'),
      ),
      body: StreamBuilder<List<DisciplineCase>>(
        stream: _cases,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const AppErrorDisplay(
              failure: CourseworkFailure(
                'Could not load the cases. Check your connection and '
                'permissions.',
              ),
            );
          }
          final cases = snapshot.data;
          if (cases == null) return const AppLoadingIndicator();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              Text(
                '${widget.student.name} · ${widget.student.nsin}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (cases.isEmpty) const Text('No cases recorded.'),
              for (final item in cases)
                CaseCard(item: item, staff: true, onTap: () => _edit(item)),
            ],
          );
        },
      ),
    );
  }
}

class _CaseDialog extends StatefulWidget {
  final DisciplineRepository repository;
  final String nsin;

  /// The case being changed, or null for a new one.
  final DisciplineCase? item;

  const _CaseDialog({
    required this.repository,
    required this.nsin,
    required this.item,
  });

  @override
  State<_CaseDialog> createState() => _CaseDialogState();
}

class _CaseDialogState extends State<_CaseDialog> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.item?.id ?? widget.repository.newId();
  late final _date = TextEditingController(
    text: widget.item?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  late final _offence = TextEditingController(text: widget.item?.offence);
  late final _action = TextEditingController(text: widget.item?.action);
  late CaseStatus _status = widget.item?.status ?? CaseStatus.open;
  late bool _visible = widget.item?.visible ?? false;
  bool _busy = false;
  AppFailure? _error;

  @override
  void dispose() {
    _date.dispose();
    _offence.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        DisciplineCase(
          id: _id,
          nsin: widget.nsin,
          date: _date.text,
          offence: _offence.text.trim(),
          action: _action.text.trim(),
          status: _status,
          visible: _visible,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Record a case' : 'Change case'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DateField(controller: _date, label: 'Date'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _offence,
              decoration: const InputDecoration(labelText: 'Offence'),
              maxLength: DisciplineCase.maxText,
              minLines: 1,
              maxLines: 4,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Describe the offence' : null,
            ),
            TextFormField(
              controller: _action,
              decoration: const InputDecoration(labelText: 'Action taken'),
              maxLength: DisciplineCase.maxText,
              minLines: 1,
              maxLines: 4,
            ),
            DropdownButtonFormField<CaseStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final status in CaseStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (status) => _status = status ?? _status,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Student can see this'),
              value: _visible,
              onChanged:
                  _busy ? null : (value) => setState(() => _visible = value),
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
