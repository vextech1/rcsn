import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/student_fee.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../core/errors/app_failure.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../fee_status_label.dart';

/// Bursar landing screen: every tuition record, with search, a status filter
/// and totals for what is shown.
class BursarDashboardScreen extends StatefulWidget {
  const BursarDashboardScreen({super.key});

  @override
  State<BursarDashboardScreen> createState() => _BursarDashboardScreenState();
}

class _BursarDashboardScreenState extends State<BursarDashboardScreen> {
  final _records = FeeRepository().watchAll();
  String _search = '';
  FeeStatus? _filter; // null = all

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bursar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Public Space',
            onPressed: () => context.push(AppRoutes.publicHome),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) context.go(AppRoutes.roleSelect);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.bursarAdd),
        icon: const Icon(Icons.person_add),
        label: const Text('Add student'),
      ),
      body: StreamBuilder<List<StudentFee>>(
        stream: _records,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorDisplay(
              failure: UnknownFailure(snapshot.error.toString()),
            );
          }
          if (!snapshot.hasData) return const AppLoadingIndicator();

          final all = snapshot.data!;
          if (all.isEmpty) {
            return const AppEmptyState(
              icon: Icons.payments,
              title: 'No fee records yet',
              message: 'Tap "Add student" to open the first one.',
            );
          }

          final query = _search.trim().toLowerCase();
          final shown = all
              .where((f) => _filter == null || f.status == _filter)
              .where((f) =>
                  f.name.toLowerCase().contains(query) ||
                  f.nsin.toLowerCase().contains(query) ||
                  f.paymentNumber.toLowerCase().contains(query))
              .toList();
          final collected = shown.fold<int>(0, (sum, f) => sum + f.paid);
          // Overpayments by one student do not reduce what others owe.
          final owed = shown.fold<int>(
              0, (sum, f) => sum + (f.balance > 0 ? f.balance : 0));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search name, NSIN or payment number',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final status in [null, ...FeeStatus.values])
                      ChoiceChip(
                        label: Text(status?.label ?? 'All'),
                        selected: _filter == status,
                        onSelected: (_) => setState(() => _filter = status),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${shown.length} records · Paid ${formatUgx(collected)} · '
                  'Owed ${formatUgx(owed)}',
                  textAlign: TextAlign.center,
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final fee = shown[i];
                    return ListTile(
                      title: Text(fee.name),
                      subtitle: Text(
                        '${fee.paymentNumber} · ${fee.nsin}\nYear ${fee.year}, Sem ${fee.semester} · '
                        'Balance ${formatUgx(fee.balance)}',
                      ),
                      isThreeLine: true,
                      trailing: FeeStatusLabel(fee.status),
                      onTap: () => context.push(
                        AppRoutes.bursarRecord,
                        extra: fee.id,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
