import 'package:flutter/material.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/staff_account.dart';
import '../../../data/repositories/staff_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Staff management, Principal only: list staff, add a Registrar or
/// Bursar, suspend or reactivate them, and re-send a set-password invite.
///
/// All changes go through StaffRepository. The route guard limits this
/// screen to the Principal, and the Firestore rules re-check that on every
/// write (the project runs on Spark, so there are no Cloud Functions).
class PrincipalStaffScreen extends StatefulWidget {
  const PrincipalStaffScreen({super.key});

  @override
  State<PrincipalStaffScreen> createState() => _PrincipalStaffScreenState();
}

class _PrincipalStaffScreenState extends State<PrincipalStaffScreen> {
  final _repository = StaffRepository();
  String? _busyId;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addStaff() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddStaffDialog(repository: _repository),
    );
    if (created == true) {
      _snack('Account created. An email was sent so they can set a password.');
    }
  }

  Future<void> _toggleStatus(StaffAccount staff) async {
    final suspending = staff.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(suspending ? 'Suspend ${staff.name}?' : 'Reactivate ${staff.name}?'),
        content: Text(
          suspending
              ? 'They will be signed out and unable to sign in until you '
                  'reactivate them.'
              : 'They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(suspending ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyId = staff.id);
    try {
      await _repository.setStatus(
        staffId: staff.id,
        status: suspending ? StaffStatus.suspended : StaffStatus.active,
      );
      _snack(suspending ? '${staff.name} suspended.' : '${staff.name} reactivated.');
    } on AppFailure catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _resendInvite(StaffAccount staff) async {
    setState(() => _busyId = staff.id);
    try {
      await _repository.resendInvite(staff.email);
      _snack('Invite sent to ${staff.email}.');
    } on AppFailure catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add),
        label: const Text('Add staff'),
      ),
      body: StreamBuilder<List<StaffAccount>>(
        stream: _repository.watchAllStaff(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorDisplay(
              failure: UnknownFailure(snapshot.error.toString()),
            );
          }
          if (!snapshot.hasData) return const AppLoadingIndicator();

          final staff = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: staff.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _StaffTile(
              staff: staff[i],
              busy: _busyId == staff[i].id,
              onToggleStatus: () => _toggleStatus(staff[i]),
              onResendInvite: () => _resendInvite(staff[i]),
            ),
          );
        },
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  final StaffAccount staff;
  final bool busy;
  final VoidCallback onToggleStatus;
  final VoidCallback onResendInvite;

  const _StaffTile({
    required this.staff,
    required this.busy,
    required this.onToggleStatus,
    required this.onResendInvite,
  });

  @override
  Widget build(BuildContext context) {
    final isPrincipal = staff.role == UserRole.principal;

    return ListTile(
      title: Text(staff.name),
      subtitle: Text(
        '${staff.email}\n${staff.role.label}'
        '${staff.isActive ? '' : ' · Suspended'}',
      ),
      isThreeLine: true,
      leading: Icon(
        staff.isActive ? Icons.verified_user : Icons.block,
        color: staff.isActive ? AppColors.primary : AppColors.error,
      ),
      trailing: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : isPrincipal
              ? null
              : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'toggle') onToggleStatus();
                    if (value == 'invite') onResendInvite();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(staff.isActive ? 'Suspend' : 'Reactivate'),
                    ),
                    const PopupMenuItem(
                      value: 'invite',
                      child: Text('Resend invite'),
                    ),
                  ],
                ),
    );
  }
}

class _AddStaffDialog extends StatefulWidget {
  final StaffRepository repository;
  const _AddStaffDialog({required this.repository});

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  UserRole _role = UserRole.registrar;
  bool _submitting = false;
  AppFailure? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.repository.createStaff(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        role: _role,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _nameController,
                label: 'Full name',
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter the full name'
                    : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _emailController,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                    value: UserRole.registrar,
                    label: Text('Registrar'),
                  ),
                  ButtonSegment(
                    value: UserRole.bursar,
                    label: Text('Bursar'),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: _submitting
                    ? null
                    : (selection) => setState(() => _role = selection.first),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AppInlineError(failure: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
