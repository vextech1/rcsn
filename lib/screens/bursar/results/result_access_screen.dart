import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/models/student_record.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/student_repository.dart';
import '../../../data/repositories/uhpab_repository.dart';
import '../../../core/utils/student_number.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// The Bursar decides which students with unpaid or unrecorded fees may still
/// see their UHPAB results.
class ResultAccessScreen extends StatefulWidget {
  const ResultAccessScreen({super.key});

  @override
  State<ResultAccessScreen> createState() => _ResultAccessScreenState();
}

class _ResultAccessScreenState extends State<ResultAccessScreen> {
  final _repository = UhpabRepository();
  final _students = StudentRepository().watchAllStudents();
  final _fees = FeeRepository().watchAll();
  late final _allowed = _repository.watchAllowed();
  String _search = '';

  /// Why the fees hold the results, or null if they are cleared. The Worker
  /// applies the same test.
  static String? _hold(List<StudentFee> records) {
    if (records.isEmpty) return 'No fee record';
    if (records.any((f) => f.tuition <= 0)) return 'Tuition not entered';
    final owed = records.fold<int>(
      0,
      (sum, f) => sum + (f.balance > 0 ? f.balance : 0),
    );
    return owed > 0 ? 'Balance ${formatUgx(owed)}' : null;
  }

  Future<void> _set(StudentRecord student, bool allowed) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(allowed ? 'Allow viewing?' : 'Stop allowing?'),
        content: Text(
          allowed
              ? '${student.name} will see published UHPAB results despite the '
                  'fees, until you turn this off.'
              : 'Unpaid fees will hide the UHPAB results of ${student.name} '
                  'again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.setAllowed(student.nsin, allowed);
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Shows [build] once the stream has data.
  Widget _when<T>(Stream<T> stream, Widget Function(T) build) =>
      StreamBuilder<T>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const AppErrorDisplay(
              failure: FeeFailure(
                'Could not load. Check your connection and permissions.',
              ),
            );
          }
          final data = snapshot.data;
          return data == null ? const AppLoadingIndicator() : build(data);
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UHPAB result access')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search name or student number',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Expanded(
            child: _when(
              _students,
              (students) => _when(
                _fees,
                (fees) => _when(
                  _allowed,
                  (allowed) => _list(students, fees, allowed),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    List<StudentRecord> students,
    List<StudentFee> fees,
    Set<String> allowed,
  ) {
    final query = _search.trim().toLowerCase();
    final shown = [
      for (final s in students)
        if (s.name.toLowerCase().contains(query) ||
            s.nsin.toLowerCase().contains(query))
          s,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (shown.isEmpty) return const Center(child: Text('No student matches.'));
    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final student = shown[i];
        final hold = _hold([
          for (final f in fees)
            if (f.nsin == student.nsin) f,
        ]);
        final isAllowed =
            allowed.contains(StudentNumber.bioKey(student.nsin));
        return SwitchListTile(
          title: Text(student.name),
          subtitle: Text(
            '${student.nsin}\n'
            '${hold == null ? 'Fees cleared' : '$hold · ${isAllowed ? 'Allowed by Bursar' : 'Results held'}'}',
          ),
          isThreeLine: true,
          // On means "allowed despite the fees".
          value: isAllowed,
          onChanged: hold == null && !isAllowed
              ? null
              : (value) => _set(student, value),
        );
      },
    );
  }
}
