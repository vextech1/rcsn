import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/content_repository.dart';
import '../../../widgets/forms/app_text_field.dart';

/// First-run Admin account creation — per Section 2.1, there is exactly
/// one Admin account, created once via this screen, with no ordinary
/// self-registration path.
///
/// RoleSelectScreen already checked AdminRepository.adminExists() before
/// routing here, so under normal use this screen should only ever be
/// reached when no Admin exists yet. But that check and this screen's
/// submission are two separate moments in time — AdminRepository.
/// createAdmin() independently re-checks adminExists() right before
/// writing (see that method's own doc comment on the race it's guarding
/// against), so this screen doesn't need its own extra existence check.
/// What it DOES need is to handle that re-check's failure gracefully if
/// it ever fires, rather than assume it never will just because
/// RoleSelectScreen already looked.
class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({super.key});

  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _adminRepository = AdminRepository();
  final _contentRepository = ContentRepository();

  bool _isSubmitting = false;
  AppFailure? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _error = const UnknownFailure('Passwords do not match.');
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _adminRepository.createAdmin(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Seed the four default content-type categories (Timetable,
      // Revision Notes, Past Papers, Announcements) so the app is
      // usable from day one, per content_types.dart's own doc comment.
      // Safe to call even if this somehow runs twice — the method
      // checks for existing types first. Best-effort: if this fails
      // (e.g. a transient network blip right after account creation),
      // don't block Admin from reaching the dashboard over it — Admin
      // can still add types manually from the Content Types screen.
      try {
        await _contentRepository.seedDefaultContentTypesIfNeeded();
      } catch (_) {
        // Deliberately swallowed — see comment above.
      }
      if (!mounted) return;
      context.go(AppRoutes.adminDashboard);
    } on AppFailure catch (e) {
      // Covers the exactly-one-Admin race condition described in the
      // class doc above: if createAdmin's internal re-check finds an
      // Admin now exists (created by someone else in the gap between
      // RoleSelectScreen's check and this submission), the person
      // submitting this form sees a clear message and gets redirected
      // to login, rather than a generic error or a silent failure.
      setState(() => _error = e);
      if (e is AdminAlreadyExistsFailure) {
        if (mounted) context.go(AppRoutes.adminLogin);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Setup')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create the Admin account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This is a one-time setup. Only one Admin account can '
                'exist for RCSN.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              AppTextField(
                controller: _nameController,
                label: 'Full Name',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _emailController,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _passwordController,
                label: 'Password',
                obscureText: true,
                validator: (v) => (v == null || v.length < 8)
                    ? 'At least 8 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                obscureText: true,
                error: _error,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create Admin Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
