import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/fee_view.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/services/fee_lookup_service.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/app_text_field.dart';
import '../../../widgets/forms/date_field.dart';
import '../../bursar/fee_status_label.dart';

/// A student's fee details, read-only.
///
/// A signed-in student enters the payment code only. With [lookup], for
/// parents, guardians and students without an NSIN, the caller also gives the
/// parent or guardian names and answers two questions. Nothing is saved,
/// because phones get shared.
class StudentFeesScreen extends StatefulWidget {
  /// True when opened without signing in.
  final bool lookup;

  const StudentFeesScreen({super.key, this.lookup = false});

  @override
  State<StudentFeesScreen> createState() => _StudentFeesScreenState();
}

class _StudentFeesScreenState extends State<StudentFeesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = FeeLookupService();
  final _code = TextEditingController();
  final _guardian = TextEditingController();
  final _answers = [TextEditingController(), TextEditingController()];
  final List<FeeQuestion?> _questions = [null, null];
  List<FeeView>? _fees;
  AppFailure? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _guardian.dispose();
    for (final answer in _answers) {
      answer.dispose();
    }
    super.dispose();
  }

  Future<void> _show() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _fees = null;
      _error = null;
    });
    try {
      final found = widget.lookup
          ? await _service.withAnswers(_code.text, _guardian.text, {
              for (var i = 0; i < 2; i++) _questions[i]!: _answers[i].text,
            })
          : await _service.forStudent(
              _code.text,
              context.read<StudentProvider>().currentStudent?.nsin ?? '',
            );
      if (mounted) setState(() => _fees = found);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String? _required(String? v) =>
      (v ?? '').trim().isEmpty ? 'Required' : null;

  List<Widget> _question(int i) {
    final question = _questions[i];
    return [
      const SizedBox(height: 16),
      DropdownButtonFormField<FeeQuestion>(
        initialValue: question,
        isExpanded: true,
        decoration: InputDecoration(labelText: 'Question ${i + 1}'),
        items: [
          // The other box's choice is left out, so the two always differ.
          for (final q in FeeQuestion.values)
            if (q != _questions[1 - i])
              DropdownMenuItem(value: q, child: Text(q.label)),
        ],
        validator: (q) => q == null ? 'Choose a question' : null,
        onChanged: (q) => setState(() {
          _questions[i] = q;
          _answers[i].clear();
        }),
      ),
      if (question == FeeQuestion.dateOfBirth)
        DateField(controller: _answers[i], label: question!.label)
      else if (question != null)
        AppTextField(
          key: ValueKey(question),
          controller: _answers[i],
          label: question.label,
          validator: _required,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lookup ? 'Student fees' : 'My fees'),
      ),
      body: Form(
        key: _formKey,
        // Not a lazy list: every field must exist when the form is checked.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _code,
                label: 'Payment code',
                validator: (v) => StudentFee.numberError(v ?? ''),
              ),
              if (widget.lookup) ...[
                const SizedBox(height: 12),
                AppTextField(
                  controller: _guardian,
                  label: 'Parent or guardian full names',
                  validator: _required,
                ),
                ..._question(0),
                ..._question(1),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _show,
                child: Text(_busy ? 'Checking…' : 'Show fees'),
              ),
              if (_error != null) AppInlineError(failure: _error!),
              for (final view in _fees ?? <FeeView>[]) _FeeCard(view),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeeCard extends StatelessWidget {
  final FeeView view;
  const _FeeCard(this.view);

  @override
  Widget build(BuildContext context) {
    final fee = view.fee;
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Year ${fee.year} · Semester ${fee.semester}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(fee.name),
            Text(fee.nsin.isEmpty ? 'No NSIN yet' : fee.nsin),
            Text('Payment code: ${fee.paymentNumber}'),
            Text(kTrackDefinitions[fee.programType]?.label ??
                fee.programType.name),
            const SizedBox(height: 8),
            Text('Tuition: ${formatUgx(fee.tuition)}'),
            Text('Paid: ${formatUgx(fee.paid)}'),
            Text(
              '${fee.balance < 0 ? 'Credit' : 'Balance'}: '
              '${formatUgx(fee.balance.abs())}',
            ),
            const SizedBox(height: 8),
            FeeStatusLabel(fee.status),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Payments'),
              children: [
                if (view.payments.isEmpty) const Text('No payments recorded.'),
                for (final p in view.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(formatUgx(p.amount)),
                    subtitle: Text(
                      '${p.method.label} · ${p.reference}'
                      '${p.recordedAt == null ? '' : '\n${DateFormat('d MMM yyyy').format(p.recordedAt!)}'}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
