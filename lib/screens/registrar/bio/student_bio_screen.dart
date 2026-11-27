import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/repositories/student_bio_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/app_text_field.dart';
import '../../../widgets/forms/date_field.dart';

/// One student's bio data, opened from the Students screen.
class StudentBioScreen extends StatefulWidget {
  /// The `student_bio` document id (see StudentNumber.bioKey), or the payment
  /// code of a student without a student number.
  final String bioKey;

  /// Who this is, for the heading.
  final String label;

  const StudentBioScreen({
    super.key,
    required this.bioKey,
    required this.label,
  });

  @override
  State<StudentBioScreen> createState() => _StudentBioScreenState();
}

class _StudentBioScreenState extends State<StudentBioScreen> {
  static const _labels = {
    'dateOfBirth': 'Date of birth',
    'district': 'Home district',
    'village': 'Village',
    'primarySchool': 'Primary school attended',
    'secondarySchool': 'Secondary school attended',
  };

  final _repository = StudentBioRepository();
  final _formKey = GlobalKey<FormState>();
  final _fields = {
    for (final f in StudentBioRepository.fields) f: TextEditingController(),
  };

  /// True once the saved details are in the form. Saving before that could
  /// overwrite them with blanks.
  bool _loaded = false;
  String? _note;
  AppFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() => _run(() async {
        final values = await _repository.load(widget.bioKey);
        if (!mounted) return;
        for (final entry in values.entries) {
          _fields[entry.key]!.text = entry.value;
        }
        _loaded = true;
      });

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _repository.save(widget.bioKey, {
        for (final entry in _fields.entries) entry.key: entry.value.text,
      });
      _note = 'Saved.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student bio data')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!_loaded && _busy) const LinearProgressIndicator(),
              if (!_loaded && _error != null)
                OutlinedButton(
                  onPressed: _busy ? null : _open,
                  child: const Text('Try again'),
                ),
              if (_loaded) ...[
                const SizedBox(height: 16),
                DateField(
                  controller: _fields['dateOfBirth']!,
                  label: _labels['dateOfBirth']!,
                ),
                for (final f in StudentBioRepository.fields.skip(1)) ...[
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _fields[f]!,
                    label: _labels[f]!,
                    validator: (v) => (v ?? '').length > 100
                        ? 'At most 100 characters'
                        : null,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ],
              if (_error != null) AppInlineError(failure: _error!),
              if (_note != null) Text(_note!),
            ],
          ),
        ),
      ),
    );
  }
}
