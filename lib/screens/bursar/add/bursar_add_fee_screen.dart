import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/nsin_validator.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/student_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/academic_structure_picker.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Opens a tuition record. "Find student" fills the details from the
/// admission record with the same NSIN; if there is none yet, the Bursar
/// types them and the record links up by NSIN. This screen never writes to
/// `students`.
class BursarAddFeeScreen extends StatefulWidget {
  /// Set when adding another semester for a student already listed.
  final StudentFee? from;

  const BursarAddFeeScreen({super.key, this.from});

  @override
  State<BursarAddFeeScreen> createState() => _BursarAddFeeScreenState();
}

class _BursarAddFeeScreenState extends State<BursarAddFeeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nsin = TextEditingController(text: widget.from?.nsin);
  late final _name = TextEditingController(text: widget.from?.name);
  late final _number =
      TextEditingController(text: widget.from?.paymentNumber);
  final _tuition = TextEditingController();

  ProgramType? _track;
  int? _year;
  int? _semester;
  int _pickerVersion = 0; // rebuilds the picker after a lookup
  String? _lookupNote;
  AppFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _track = widget.from?.programType;
    if (widget.from?.nsin.isNotEmpty ?? false) _find();
  }

  @override
  void dispose() {
    _nsin.dispose();
    _name.dispose();
    _number.dispose();
    _tuition.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final problem = NsinValidator.errorMessage(_nsin.text);
    if (problem != null) {
      setState(() => _error = UnknownFailure(problem));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _lookupNote = null;
    });
    try {
      final student = await StudentRepository().findByNsin(_nsin.text);
      final number = await FeeRepository().numberFor(_nsin.text);
      if (!mounted) return;
      setState(() {
        if (number != null) _number.text = number;
        if (student == null) {
          _lookupNote = 'Not admitted yet. Enter the details below.';
        } else {
          _name.text = student.name;
          _track = student.programType;
          _year = student.year;
          _semester = student.semester;
          _pickerVersion++;
          _lookupNote = 'Admission record found.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = const UnknownFailure(
            'Could not look up the student. Check your connection.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_track == null || _year == null || _semester == null) {
      setState(() => _error =
          const UnknownFailure('Select the program, year and semester.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await FeeRepository().create(
        paymentNumber: _number.text,
        nsin: _nsin.text,
        name: _name.text,
        programType: _track!,
        year: _year!,
        semester: _semester!,
        tuition: parseUgx(_tuition.text)!,
      );
      if (mounted) {
        context.pushReplacement(AppRoutes.bursarRecord, extra: id);
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add student fees')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppTextField(
              controller: _nsin,
              label: 'NSIN (leave empty if not yet given)',
              validator: (v) => (v ?? '').trim().isEmpty
                  ? null
                  : NsinValidator.errorMessage(v!),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _find,
              icon: const Icon(Icons.search),
              label: const Text('Find student'),
            ),
            if (_lookupNote != null) Text(_lookupNote!),
            const SizedBox(height: 12),
            AppTextField(
              controller: _name,
              label: 'Full name',
              validator: (v) {
                final length = (v ?? '').trim().length;
                return length < 2 || length > 100
                    ? 'Enter the full name'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            AcademicStructurePicker(
              key: ValueKey(_pickerVersion),
              initialTrack: _track,
              initialYear: _year,
              initialSemester: _semester,
              onChanged: (track, year, semester) {
                _track = track;
                _year = year;
                _semester = semester;
              },
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _number,
              label: 'Payment code',
              validator: (v) => StudentFee.numberError(v ?? ''),
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
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
