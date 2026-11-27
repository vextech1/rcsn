import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/staff_account.dart';
import '../../../data/models/staff_position.dart';
import '../../../data/repositories/staff_position_repository.dart';
import '../../../data/repositories/staff_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Staff management for the Principal and the Deputy Principal: list staff,
/// add someone in any position, manage the list of custom positions, suspend
/// or reactivate staff, and re-send a set-password invite.
///
/// The Principal is above the Deputy Principal: only the Principal can
/// appoint the Deputy, and only the Principal can terminate them (one-way).
/// The Deputy can manage everyone else. The Principal's own record is never
/// editable.
///
/// All changes go through StaffRepository. The route guard limits this
/// screen to the Principal and Deputy Principal, and the Firestore rules
/// re-check every write (the project runs on Spark, so there are no Cloud
/// Functions).
class PrincipalStaffScreen extends StatefulWidget {
  const PrincipalStaffScreen({super.key});

  @override
  State<PrincipalStaffScreen> createState() => _PrincipalStaffScreenState();
}

class _PrincipalStaffScreenState extends State<PrincipalStaffScreen> {
  final _repository = StaffRepository();
  final _positionRepository = StaffPositionRepository();
  String? _busyId;

  bool get _viewerIsPrincipal =>
      context.read<AuthProvider>().resolvedRole == UserRole.principal;

  /// Whether the signed-in person may suspend, terminate or reactivate
  /// [staff]. Mirrors the `staff` update rule in firestore.rules.
  bool _canManage(StaffAccount staff) {
    if (staff.role == UserRole.principal) return false;
    if (staff.role == UserRole.deputyPrincipal) {
      // Only the Principal, and only to terminate (never reactivate).
      return _viewerIsPrincipal && staff.isActive;
    }
    return true;
  }

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
      builder: (_) => _AddStaffDialog(
        repository: _repository,
        positionRepository: _positionRepository,
        canAddDeputy: _viewerIsPrincipal,
      ),
    );
    if (created == true) {
      _snack('Account created. An email was sent so they can set a password.');
    }
  }

  Future<void> _managePositions() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PositionsDialog(repository: _positionRepository),
    );
  }

  Future<void> _toggleStatus(StaffAccount staff) async {
    final suspending = staff.isActive;
    final terminating = staff.role == UserRole.deputyPrincipal;

    final String title;
    final String body;
    final String action;
    if (terminating) {
      title = 'Terminate ${staff.name}?';
      body = 'They will lose all Deputy Principal access straight away and '
          'cannot be reinstated. The Deputy Principal option will appear on '
          'the Staff screen again so you can appoint someone else.';
      action = 'Terminate';
    } else if (suspending) {
      title = 'Suspend ${staff.name}?';
      body = 'They will be signed out and unable to sign in until you '
          'reactivate them.';
      action = 'Suspend';
    } else {
      title = 'Reactivate ${staff.name}?';
      body = 'They will be able to sign in again.';
      action = 'Reactivate';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
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
        targetRole: staff.role,
      );
      _snack(
        terminating
            ? '${staff.name} terminated.'
            : suspending
                ? '${staff.name} suspended.'
                : '${staff.name} reactivated.',
      );
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
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Positions',
            onPressed: _managePositions,
          ),
        ],
      ),
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
              canManage: _canManage(staff[i]),
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
  final bool canManage;
  final VoidCallback onToggleStatus;
  final VoidCallback onResendInvite;

  const _StaffTile({
    required this.staff,
    required this.busy,
    required this.canManage,
    required this.onToggleStatus,
    required this.onResendInvite,
  });

  @override
  Widget build(BuildContext context) {
    final isDeputy = staff.role == UserRole.deputyPrincipal;
    final inactiveLabel = isDeputy ? ' · Terminated' : ' · Suspended';

    String toggleLabel;
    if (isDeputy) {
      toggleLabel = 'Terminate';
    } else {
      toggleLabel = staff.isActive ? 'Suspend' : 'Reactivate';
    }

    return ListTile(
      title: Text(staff.name),
      subtitle: Text(
        '${staff.email}\n${staff.positionLabel}'
        '${staff.isActive ? '' : inactiveLabel}',
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
          : !canManage
              ? null
              : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'toggle') onToggleStatus();
                    if (value == 'invite') onResendInvite();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(toggleLabel),
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
  final StaffPositionRepository positionRepository;

  /// Only the Principal can appoint a Deputy Principal.
  final bool canAddDeputy;

  const _AddStaffDialog({
    required this.repository,
    required this.positionRepository,
    required this.canAddDeputy,
  });

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  List<StaffPosition> _options = const [];
  StaffPosition? _selected;
  bool _loadingPositions = true;
  bool _submitting = false;
  AppFailure? _error;

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadPositions() async {
    final builtIn = <StaffPosition>[
      StaffPosition.registrar,
      StaffPosition.bursar,
      if (widget.canAddDeputy) StaffPosition.deputyPrincipal,
    ];
    var custom = <StaffPosition>[];
    try {
      custom = await widget.positionRepository.fetchCustomPositions();
    } catch (_) {
      // Still usable with the built-in positions.
    }
    if (!mounted) return;
    setState(() {
      _options = [...builtIn, ...custom];
      _selected = _options.first;
      _loadingPositions = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final position = _selected;
    if (position == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.repository.createStaff(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        role: position.role,
        position: position.isCustom ? position.title : null,
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
              if (_loadingPositions)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                DropdownButtonFormField<StaffPosition>(
                  value: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Position'),
                  items: [
                    for (final p in _options)
                      DropdownMenuItem<StaffPosition>(
                        value: p,
                        child: Text(p.title),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (p) => setState(() => _selected = p),
                ),
              const SizedBox(height: 8),
              const Text(
                'Need a position that is not listed (Askari, Accountant, ...)? '
                'Close this and tap the list icon at the top to add it first.',
                style: TextStyle(fontSize: 12, color: AppColors.textMid),
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
          onPressed: (_submitting || _selected == null) ? null : _submit,
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

/// The custom positions shown on the Staff screen before sign-in.
class _PositionsDialog extends StatefulWidget {
  final StaffPositionRepository repository;
  const _PositionsDialog({required this.repository});

  @override
  State<_PositionsDialog> createState() => _PositionsDialogState();
}

class _PositionsDialogState extends State<_PositionsDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  AppFailure? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.addPosition(_controller.text);
      _controller.clear();
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(StaffPosition position) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${position.title}?'),
        content: const Text(
          'It will no longer appear on the Staff screen, so people in this '
          'position will not be able to pick it to sign in. Their accounts '
          'are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.removePosition(position.id);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Positions'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Shown on the Staff screen before sign-in. Principal, Deputy '
              'Principal, Registrar and Bursar are always there.',
              style: TextStyle(fontSize: 12, color: AppColors.textMid),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: StreamBuilder<List<StaffPosition>>(
                stream: widget.repository.watchCustomPositions(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Could not load positions.');
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final positions = snapshot.data!;
                  if (positions.isEmpty) {
                    return const Text('No custom positions yet.');
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: positions.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(positions[i].title),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove',
                        onPressed: _busy ? null : () => _remove(positions[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'New position (e.g. Askari)',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  tooltip: 'Add',
                  onPressed: _busy ? null : _add,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              AppInlineError(failure: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
