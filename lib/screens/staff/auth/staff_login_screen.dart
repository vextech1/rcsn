import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/models/staff_position.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Staff login, shared by every staff position (Principal, Deputy Principal,
/// Registrar, Bursar and the custom positions).
///
/// [position] is what the person picked on the Staff screen. It is passed to
/// [AuthProvider.signIn], which rejects the sign-in if the account is in a
/// different position. It is null when the router sent someone here (for
/// example a signed-out visit to a staff-only screen); the sign-in then works
/// as before and the account alone decides the dashboard.
///
/// Uses [AuthProvider.signIn], same as Tutor login. Which dashboard the
/// person lands on is decided after sign-in by AuthProvider (reading the
/// `staff` record) and the router guard, not by this screen. There is no
/// register link: staff accounts are created by the Principal or Deputy
/// Principal.
///
/// IMPORTANT: this screen watches AuthProvider directly (via
/// context.watch) rather than only catching what signIn() throws.
/// signIn() only awaits the Firebase Auth call; role resolution happens
/// moments later in AuthProvider's auth-state listener. A failure there
/// (no matching staff record, a suspended account) would otherwise never
/// reach this screen. Watching [AuthProvider.lastError] and
/// [AuthProvider.isResolving] closes that gap.
class StaffLoginScreen extends StatefulWidget {
  final StaffPosition? position;

  const StaffLoginScreen({super.key, this.position});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
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
            position: widget.position,
          );
      // No manual navigation here. The router's redirect guard sends a
      // resolved staff session to the right dashboard on its own. If
      // resolution fails instead (wrong credentials, no staff record,
      // suspended), AuthProvider.lastError surfaces it below, not this
      // try/catch, which only covers the synchronous Firebase Auth call.
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
      appBar: AppBar(
        title: Text(
          widget.position == null
              ? 'Staff Login'
              : '${widget.position!.title} Login',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              if (widget.position != null && !widget.position!.isSingleHolder) ...[
                const Text(
                  'Your account is created by the Principal or Deputy '
                  'Principal. If you do not have one yet, ask them to add you.',
                ),
                const SizedBox(height: 20),
              ],
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
