import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/app_text_field.dart';
import '../fee_status_label.dart';

/// One student's semester: info, tuition, paid, balance, status and the
/// payment history.
class BursarFeeDetailScreen extends StatefulWidget {
  final String feeId;
  const BursarFeeDetailScreen({super.key, required this.feeId});

  @override
  State<BursarFeeDetailScreen> createState() => _BursarFeeDetailScreenState();
}

class _BursarFeeDetailScreenState extends State<BursarFeeDetailScreen> {
  final _repository = FeeRepository();
  late final _fee = _repository.watch(widget.feeId);
  late final _payments = _repository.watchPayments(widget.feeId);

  Future<void> _recordPayment() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(
        repository: _repository,
        feeId: widget.feeId,
      ),
    );
  }

  Future<void> _editTuition(StudentFee fee) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TuitionDialog(repository: _repository, fee: fee),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fee record')),
      body: StreamBuilder<StudentFee?>(
        stream: _fee,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorDisplay(
              failure: UnknownFailure(snapshot.error.toString()),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator();
          }
          final fee = snapshot.data;
          if (fee == null) {
            return const AppEmptyState(
              icon: Icons.payments,
              title: 'Record not found',
              message: 'Go back and choose a student.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(fee.name, style: Theme.of(context).textTheme.headlineSmall),
              Text(fee.nsin),
              Text(kTrackDefinitions[fee.programType]?.label ??
                  fee.programType.name),
              Text('Year ${fee.year} · Semester ${fee.semester}'),
              const SizedBox(height: 16),
              _row('Tuition', formatUgx(fee.tuition)),
              _row('Paid', formatUgx(fee.paid)),
              _row(
                fee.balance < 0 ? 'Credit' : 'Balance',
                formatUgx(fee.balance.abs()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FeeStatusLabel(fee.status),
              ),
              FilledButton.icon(
                onPressed: _recordPayment,
                icon: const Icon(Icons.add),
                label: const Text('Record payment'),
              ),
              OutlinedButton(
                onPressed: () => _editTuition(fee),
                child: const Text('Change tuition'),
              ),
              OutlinedButton(
                onPressed: () => context.push(
                  AppRoutes.bursarAdd,
                  extra: fee.nsin,
                ),
                child: const Text('Add another semester'),
              ),
              const Divider(height: 32),
              Text('Payments', style: Theme.of(context).textTheme.titleMedium),
              _history(),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _history() => StreamBuilder<List<FeePayment>>(
        stream: _payments,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Could not load the payments.');
          }
          final payments = snapshot.data ?? [];
          if (payments.isEmpty) return const Text('No payments recorded.');
          return Column(
            children: [
              for (final p in payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(formatUgx(p.amount)),
                  subtitle: Text(
                    '${p.method.label} · ${p.reference}'
                    '${p.recordedAt == null ? '' : '\n${DateFormat('d MMM yyyy, HH:mm').format(p.recordedAt!)}'}',
                  ),
                ),
            ],
          );
        },
      );
}

class _PaymentDialog extends StatefulWidget {
  final FeeRepository repository;
  final String feeId;
  const _PaymentDialog({required this.repository, required this.feeId});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.bank;
  AppFailure? _error;
  bool _busy = false;

  bool get _isCorrection => _method == PaymentMethod.correction;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.recordPayment(
        widget.feeId,
        FeePayment(
          amount: parseUgx(_amount.text, allowNegative: _isCorrection)!,
          method: _method,
          reference: _reference.text,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record payment'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: [
                  for (final m in PaymentMethod.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) => setState(() => _method = m!),
              ),
              AppTextField(
                controller: _amount,
                label: _isCorrection
                    ? 'Amount (use - to subtract)'
                    : 'Amount (UGX)',
                keyboardType: _isCorrection
                    ? const TextInputType.numberWithOptions(signed: true)
                    : TextInputType.number,
                validator: (v) {
                  final value =
                      parseUgx(v ?? '', allowNegative: _isCorrection);
                  return value == null || value == 0 ? 'Enter an amount' : null;
                },
              ),
              AppTextField(
                controller: _reference,
                label: _isCorrection ? 'Reason' : 'Receipt or slip number',
                validator: (v) {
                  final length = (v ?? '').trim().length;
                  return length < 1 || length > 100 ? 'Required' : null;
                },
              ),
              if (_error != null) AppInlineError(failure: _error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TuitionDialog extends StatefulWidget {
  final FeeRepository repository;
  final StudentFee fee;
  const _TuitionDialog({required this.repository, required this.fee});

  @override
  State<_TuitionDialog> createState() => _TuitionDialogState();
}

class _TuitionDialogState extends State<_TuitionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _tuition = TextEditingController(text: '${widget.fee.tuition}');
  AppFailure? _error;
  bool _busy = false;

  @override
  void dispose() {
    _tuition.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository
          .setTuition(widget.fee.id, parseUgx(_tuition.text)!);
      if (mounted) Navigator.of(context).pop();
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change tuition'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _tuition,
              label: 'Semester tuition (UGX)',
              keyboardType: TextInputType.number,
              validator: (v) => (parseUgx(v ?? '') ?? 0) > 0
                  ? null
                  : 'Enter the tuition in shillings',
            ),
            if (_error != null) AppInlineError(failure: _error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
