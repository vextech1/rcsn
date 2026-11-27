import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/nsin_validator.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/app_text_field.dart';
import '../../bursar/fee_status_label.dart';

/// A student's fee details, read-only. Parents open it without signing in and
/// enter either the NSIN or the payment code; a signed-in student sees theirs
/// straight away. Nothing is saved, because phones get shared.
class StudentFeesScreen extends StatefulWidget {
  /// True when opened without signing in.
  final bool lookup;

  const StudentFeesScreen({super.key, this.lookup = false});

  @override
  State<StudentFeesScreen> createState() => _StudentFeesScreenState();
}

class _StudentFeesScreenState extends State<StudentFeesScreen> {
  final _input = TextEditingController();
  List<StudentFee>? _fees;
  AppFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.lookup) {
      _input.text =
          context.read<StudentProvider>().currentStudent?.nsin ?? '';
      _show();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    // An NSIN has slashes; a payment code never does.
    final isNsin = _input.text.contains('/');
    final problem = isNsin
        ? NsinValidator.errorMessage(_input.text)
        : StudentFee.numberError(_input.text);
    if (problem != null) {
      setState(() {
        _fees = null;
        _error = const FeeFailure('Enter a valid NSIN or payment code.');
      });
      return;
    }
    setState(() {
      _busy = true;
      _fees = null;
      _error = null;
    });
    try {
      final repository = FeeRepository();
      final found = isNsin
          ? await repository.findByNsin(_input.text)
          : await repository.findByNumber(_input.text);
      if (!mounted) return;
      setState(() {
        if (found.isEmpty) {
          _error = const FeeFailure(
            'No fees found. Check the number or ask the Bursar.',
          );
        } else {
          _fees = found;
        }
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lookup ? 'Student fees' : 'My fees'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppTextField(controller: _input, label: 'NSIN or payment code'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _show,
            child: Text(_busy ? 'Loading…' : 'Show fees'),
          ),
          if (_error != null) AppInlineError(failure: _error!),
          for (final fee in _fees ?? <StudentFee>[])
            Card(
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
                    _PaymentHistory(key: ValueKey(fee.id), feeId: fee.id),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loaded only when opened, to save reads.
class _PaymentHistory extends StatelessWidget {
  final String feeId;
  const _PaymentHistory({super.key, required this.feeId});

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Payments'),
        children: [
          StreamBuilder<List<FeePayment>>(
            stream: FeeRepository().watchPayments(feeId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Could not load the payments.');
              }
              final payments = snapshot.data;
              if (payments == null) return const Text('Loading…');
              if (payments.isEmpty) return const Text('No payments recorded.');
              return Column(
                children: [
                  for (final p in payments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(formatUgx(p.amount)),
                      subtitle: Text(
                        '${p.method.label} · ${p.reference}'
                        '${p.recordedAt == null ? '' : '\n${DateFormat('d MMM yyyy').format(p.recordedAt!)}'}',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}
