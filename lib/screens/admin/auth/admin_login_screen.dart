import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Admin login. Shares [AuthProvider.signIn] with Tutor login — the same
/// method per Section 2.4's permission table showing both roles use
/// email+password, and role resolution after sign-in is AuthProvider's
/// job (checking AdminRepository then TutorRepository), not something
/// this screen decides.
///
/// Unlike TutorLoginScreen, there is no "register" link here — per
/// Section 2.1, Admin has no self-registration screen. The one Admin
/// account is created once via AdminSetupScreen's first-run flow, not
/// from this screen.
///
/// IMPORTANT: this screen watches AuthProvider directly (via
/// context.watch) rather than only catching whatever signIn() throws
/// synchronously. signIn() itself only awaits the Firebase Auth call —
/// role resolution (checking whether a matching Admin/Tutor document
/// exists) happens moments later, asynchronously, inside AuthProvider's
/// own auth-state listener. A failure there (including "signed in but
/// no matching account exists," e.g. after a Firestore document was
/// deleted while a device still held a valid cached Auth session) would
/// otherwise never reach this screen — the button would just return to
/// idle with signIn() reporting success, and the router would silently
/// bounce back to this same route with zero explanation. Watching
/// [AuthProvider.lastError] and [AuthProvider.isResolving] directly is
/// what closes that gap.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await context.read<AuthProvider>().signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // No manual navigation here. The router's redirect guard sends a
      // resolved Admin session to AdminDashboard on its own once
      // AuthProvider resolves the role. If resolution instead fails
      // (wrong credentials, or a signed-in-but-no-matching-account
      // state), AuthProvider.lastError is what surfaces that below —
      // not this try/catch, which only covers the synchronous
      // Firebase Auth call itself.
    } on AppFailure catch (_) {
      // Already recorded on AuthProvider.lastError by signIn() before
      // it rethrows — the watch()'d build() below picks it up. Caught
      // here only so this Future doesn't complete as an unhandled
      // rejection; nothing further to do with it in this method.
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Covers both the synchronous sign-in failure (wrong password,
    // unknown email — set immediately by signIn()) and the asynchronous
    // role-resolution failure described in the class doc comment above
    // (set moments later by the auth-state listener). Both land in the
    // same AuthProvider.lastError, so this screen only needs to watch
    // one field to catch either.
    final error = auth.lastError;
    final isBusy = _isSubmitting || auth.isResolving;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
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
                error: error,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isBusy ? null : _submit,
                child: isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Log In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
