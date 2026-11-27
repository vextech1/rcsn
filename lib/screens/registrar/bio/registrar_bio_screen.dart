import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/student_number.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/student_bio_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/app_text_field.dart';
import '../../../widgets/forms/date_field.dart';

/// The Registrar records a student's bio data, under the NSIN or, for a new
/// student, the payment code.
class RegistrarBioScreen extends StatefulWidget {
  const RegistrarBioScreen({super.key});

  @override
  State<RegistrarBioScreen> createState() => _RegistrarBioScreenState();
}

class _RegistrarBioScreenState extends State<RegistrarBioScreen> {
  static const _labels = {
    'dateOfBirth': 'Date of birth',
    'district': 'Home district',
    'village': 'Village',
    'primarySchool': 'Primary school attended',
    'secondarySchool': 'Secondary school attended',
  };

  final _repository = StudentBioRepository();
  final _formKey = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _fields = {
    for (final f in StudentBioRepository.fields) f: TextEditingController(),
  };

  /// False when the student is identified by payment code.
  bool _byNumber = true;

  /// The bio record whose form is open; null until one is opened.
  String? _loaded;
  String? _note;
  AppFailure? _error;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
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

  Future<void> _open() async {
    // Not held to the current format: older students keep older numbers.
    final problem = _byNumber
        ? StudentNumber.basicError(_key.text)
        : StudentFee.numberError(_key.text);
    if (problem != null) {
      setState(() {
        _loaded = null;
        _error = UnknownFailure(problem);
      });
      return;
    }
    final key = _byNumber
        ? StudentNumber.bioKey(StudentNumber.normalize(_key.text))
        : StudentFee.normalizeNumber(_key.text);
    await _run(() async {
      final values = await _repository.load(key);
      // The number may have been edited while this was loading.
      if (!mounted) return;
      for (final entry in values.entries) {
        _fields[entry.key]!.text = entry.value;
      }
      _loaded = key;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _repository.save(_loaded!, {
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Student number')),
                  ButtonSegment(value: false, label: Text('Payment code')),
                ],
                selected: {_byNumber},
                onSelectionChanged: _busy
                    ? null
                    : (choice) => setState(() {
                          _byNumber = choice.first;
                          _loaded = null;
                          _note = null;
                          _error = null;
                        }),
              ),
              TextFormField(
                controller: _key,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: _byNumber
                      ? 'Student number'
                      : 'Payment code (if no student number yet)',
                ),
                // Editing the number closes the form, so details cannot be
                // saved against the wrong student.
                onChanged: (_) => setState(() {
                  _loaded = null;
                  _note = null;
                }),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _open,
                icon: const Icon(Icons.search),
                label: const Text('Open'),
              ),
              if (_loaded != null) ...[
                Text('Bio data for ${StudentNumber.normalize(_key.text)}'),
                DateField(
                  controller: _fields['dateOfBirth']!,
                  label: _labels['dateOfBirth']!,
                ),
                for (final f in StudentBioRepository.fields.skip(1))
                  AppTextField(
                    controller: _fields[f]!,
                    label: _labels[f]!,
                    validator: (v) => (v ?? '').length > 100
                        ? 'At most 100 characters'
                        : null,
                  ),
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
