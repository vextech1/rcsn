import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/student_number.dart';
import '../../../data/repositories/student_number_repository.dart';
import '../../../data/repositories/student_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// The Academic Registrar sets, edits or deletes the student number formats.
class StudentNumberFormatScreen extends StatefulWidget {
  const StudentNumberFormatScreen({super.key});

  @override
  State<StudentNumberFormatScreen> createState() =>
      _StudentNumberFormatScreenState();
}

class _StudentNumberFormatScreenState extends State<StudentNumberFormatScreen> {
  final _repository = StudentNumberRepository();
  final _formKey = GlobalKey<FormState>();
  final _fields = <TextEditingController>[];
  final _sample = TextEditingController();
  List<String> _saved = [];
  bool _loaded = false;
  bool _busy = false;
  String? _note;
  AppFailure? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    _sample.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final formats = await _repository.load();
      if (!mounted) return;
      setState(() {
        _saved = formats;
        _fields.addAll([
          for (final f in formats.isEmpty ? [''] : formats)
            TextEditingController(text: f),
        ]);
        _loaded = true;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<String> get _typed => [
        for (final c in _fields)
          if (c.text.trim().isNotEmpty) StudentNumber.normalize(c.text),
      ];

  Future<bool> _confirm(String title, String message, String action) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      await action();
    } on AppFailure catch (e) {
      _error = e;
    } catch (_) {
      _error = const UnknownFailure('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final formats = _typed;
    if (formats.isEmpty) {
      setState(() => _error = const UnknownFailure('Enter a format.'));
      return;
    }
    await _run(() async {
      // Students whose numbers do not fit could no longer sign in.
      final students = await StudentRepository().watchAllStudents().first;
      final misfits = students
          .where((s) => StudentNumber.errorFor(s.nsin, formats) != null)
          .toList();
      if (!mounted) return;
      if (misfits.isNotEmpty &&
          !await _confirm(
            'Some students will not fit',
            '${misfits.length} admitted students, such as '
                '${misfits.first.nsin}, do not fit. They will not be able to '
                'sign in. To keep them, cancel and add their format too.',
            'Save anyway',
          )) {
        return;
      }
      await _repository.save(formats);
      _saved = formats;
      _note = 'Saved.';
    });
  }

  Future<void> _delete() async {
    if (!await _confirm(
      'Delete the format?',
      'Any well-formed student number will then be accepted.',
      'Delete',
    )) {
      return;
    }
    await _run(() async {
      await _repository.delete();
      _saved = [];
      while (_fields.length > 1) {
        _fields.removeLast().dispose();
      }
      _fields.first.clear();
      _note = 'Format deleted.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student number format')),
      body: !_loaded
          ? (_error == null
              ? const AppLoadingIndicator()
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppInlineError(failure: _error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Type # for a digit, @ for a letter and * for either. '
                      'Type everything else exactly as it appears.\n'
                      'Example: @@@##/U028/@@@/### fits JAN21/U028/CCN/002',
                    ),
                    const SizedBox(height: 8),
                    Text(_saved.isEmpty
                        ? 'No format is set. Any well-formed number is accepted.'
                        : 'In use: ${_saved.join(' or ')}'),
                    for (var i = 0; i < _fields.length; i++)
                      TextFormField(
                        key: ObjectKey(_fields[i]),
                        controller: _fields[i],
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _note = null),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? null
                            : StudentNumber.formatError(v!),
                        decoration: InputDecoration(
                          labelText: 'Format ${i + 1}',
                          suffixIcon: _fields.length == 1
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Remove',
                                  onPressed: () {
                                    final removed = _fields[i];
                                    setState(() => _fields.removeAt(i));
                                    // The field still uses it until rebuilt.
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                      (_) => removed.dispose(),
                                    );
                                  },
                                ),
                        ),
                      ),
                    if (_fields.length < StudentNumber.maxFormats)
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _fields.add(TextEditingController()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add another format'),
                      ),
                    TextField(
                      controller: _sample,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Try a student number (not saved)',
                      ),
                    ),
                    if (_sample.text.trim().isNotEmpty)
                      Text(
                        StudentNumber.errorFor(_sample.text, _typed) == null
                            ? 'Accepted'
                            : 'Not accepted',
                      ),
                    if (_error != null) AppInlineError(failure: _error!),
                    if (_note != null) Text(_note!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Save'),
                    ),
                    if (_saved.isNotEmpty)
                      OutlinedButton(
                        onPressed: _busy ? null : _delete,
                        child: const Text('Delete format'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
