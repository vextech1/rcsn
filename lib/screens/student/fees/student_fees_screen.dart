import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/forms/app_text_field.dart';
import '../../bursar/fee_status_label.dart';

/// The student enters the payment code they were given and sees what the
/// Bursar holds: name, program and tuition for each semester. Read-only. The
/// code is deliberately not saved, because students share phones.
class StudentFeesScreen extends StatefulWidget {
  /// True when opened without signing in: a parent, or a new student with no
  /// NSIN yet. The school-issued code alone is enough.
  final bool codeOnly;

  const StudentFeesScreen({super.key, this.codeOnly = false});

  @override
  State<StudentFeesScreen> createState() => _StudentFeesScreenState();
}

class _StudentFeesScreenState extends State<StudentFeesScreen> {
  final _number = TextEditingController();
  List<StudentFee>? _fees;
  AppFailure? _error;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    final problem = StudentFee.numberError(_number.text);
    if (problem != null) {
      setState(() {
        _fees = null;
        _error = UnknownFailure(problem);
      });
      return;
    }
    final nsin = widget.codeOnly
        ? null
        : context.read<StudentProvider>().currentStudent?.nsin;
    setState(() {
      _busy = true;
      _fees = null;
      _error = null;
    });
    try {
      final found = await FeeRepository().findByNumber(_number.text);
      // The code alone shows its records. A signed-in student sees only their
      // own, including any not yet linked to an NSIN.
      final own = found
          .where((f) => widget.codeOnly || f.nsin.isEmpty || f.nsin == nsin)
          .toList();
      if (!mounted) return;
      setState(() {
        if (own.isEmpty) {
          _error = const FeeFailure(
            'Nothing found for that payment code. Check it or ask the Bursar.',
          );
        } else {
          _fees = own;
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
        title: Text(widget.codeOnly ? 'Fees' : 'My fees'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppTextField(controller: _number, label: 'Payment code'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _show,
            child: Text(_busy ? 'Loading…' : 'Show my fees'),
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
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
