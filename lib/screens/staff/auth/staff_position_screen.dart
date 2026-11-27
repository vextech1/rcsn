import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/staff_position.dart';
import '../../../data/repositories/staff_position_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// First screen of the Staff flow: pick the position you hold, then sign in.
///
/// The list is Principal, Deputy Principal, Registrar and Bursar plus every
/// position the Principal or Deputy Principal added (Askari, Accountant,
/// Clinical Instructor, ...). Principal and Deputy Principal drop off the
/// list once their holder has signed in, so nobody else is offered them.
///
/// Picking a position grants nothing by itself: the account is still created
/// by the Principal or Deputy Principal, and sign-in checks that the account
/// really is in the position that was picked.
class StaffPositionScreen extends StatefulWidget {
  const StaffPositionScreen({super.key});

  @override
  State<StaffPositionScreen> createState() => _StaffPositionScreenState();
}

class _StaffPositionScreenState extends State<StaffPositionScreen> {
  final _repository = StaffPositionRepository();
  late Future<List<StaffPosition>> _positions;

  @override
  void initState() {
    super.initState();
    _positions = _repository.fetchSelectable();
  }

  Future<void> _refresh() async {
    final next = _repository.fetchSelectable();
    setState(() => _positions = next);
    await next;
  }

  void _choose(StaffPosition position) {
    // Clear an error left over from an earlier, abandoned sign-in before
    // this fresh navigation (see AuthProvider.clearError).
    context.read<AuthProvider>().clearError();
    context.push(AppRoutes.staffLogin, extra: position);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      body: FutureBuilder<List<StaffPosition>>(
        future: _positions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoadingIndicator();
          }
          final positions = snapshot.data ?? StaffPosition.defaults;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              itemCount: positions.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Select your position',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                final position = positions[i - 1];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(
                      Icons.badge_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(position.title),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _choose(position),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
