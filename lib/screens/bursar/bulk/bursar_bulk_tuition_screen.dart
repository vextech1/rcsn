import 'package:flutter/material.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/academic_structure_picker.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Sets one tuition for every record of a class, after the Bursar confirms how
/// many will change. It does not open records for students who have none.
class BursarBulkTuitionScreen extends StatefulWidget {
  const BursarBulkTuitionScreen({super.key});

  @override
  State<BursarBulkTuitionScreen> createState() =>
      _BursarBulkTuitionScreenState();
}

class _BursarBulkTuitionScreenState extends State<BursarBulkTuitionScreen> {
  final _repository = FeeRepository();
  final _formKey = GlobalKey<FormState>();
  final _tuition = TextEditingController();
  ProgramType? _track;
  int? _year;
  int? _semester;
  String? _note;
  AppFailure? _error;
  bool _busy = false;

  @override
  void dispose() {
    _tuition.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    final track = _track;
    final year = _year;
    final semester = _semester;
    if (track == null || year == null || semester == null) {
      setState(() => _error =
          const UnknownFailure('Select the program, year and semester.'));
      return;
    }
    final tuition = parseUgx(_tuition.text)!;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      final records =
          await _repository.classRecords(track, year, semester);
      final changing = [
        for (final r in records)
          if (r.tuition != tuition) r,
      ];
      if (!mounted) return;
      if (changing.isEmpty) {
        setState(() => _note = records.isEmpty
            ? 'This class has no fee records yet.'
            : 'All ${records.length} records already have this tuition.');
        return;
      }
      final confirmed = await _confirm(records.length, changing, tuition);
      if (!confirmed || !mounted) return;
      await _repository.setClassTuition(changing, tuition);
      if (mounted) {
        setState(() => _note = 'Updated ${changing.length} records.');
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    int total,
    List<StudentFee> changing,
    int tuition,
  ) async {
    final owing = changing.where((r) => tuition > r.paid).length;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change class tuition?'),
        content: Text(
          '${changing.length} of $total records will change to '
          '${formatUgx(tuition)}. Afterwards $owing of them will have a '
          'balance to pay.\n\nThis replaces any different amount set for a '
          'single student.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class tuition')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AcademicStructurePicker(
                onChanged: (track, year, semester) {
                  _track = track;
                  _year = year;
                  _semester = semester;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _tuition,
                label: 'Semester tuition (UGX)',
                keyboardType: TextInputType.number,
                validator: (v) => (parseUgx(v ?? '') ?? 0) > 0
                    ? null
                    : 'Enter the tuition in shillings',
              ),
              if (_error != null) AppInlineError(failure: _error!),
              if (_note != null) Text(_note!),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _apply,
                child: Text(_busy ? 'Working…' : 'Review change'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
