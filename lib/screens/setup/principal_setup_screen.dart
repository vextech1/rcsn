import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../widgets/forms/app_text_field.dart';

/// First-run setup: the Principal registers themselves. This is the ONLY
/// screen the app shows until it has been completed, so nobody else can
/// register before the Principal (firestore.rules enforce the same thing
/// server-side). It can only ever be completed once.
class PrincipalSetupScreen extends StatefulWidget {
  const PrincipalSetupScreen({super.key});

  @override
  State<PrincipalSetupScreen> createState() => _PrincipalSetupScreenState();
}

class _PrincipalSetupScreenState extends State<PrincipalSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

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
      setState(() => _error = const UnknownFailure('Passwords do not match.'));
      return;
    }

    // Read everything needed up front: once setup completes the router
    // navigates away and this screen is disposed.
    final setup = context.read<SetupProvider>();
    final auth = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await setup.registerPrincipal(
        name: _nameController.text,
        email: email,
        password: password,
      );
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isSubmitting = false;
        });
      }
      return;
    }

    // Registered. Sign in, then let the router take over: the signed-in
    // Principal is sent to their dashboard by the usual role guard.
    try {
      await auth.signIn(
        email: email,
        password: password,
        door: LoginDoor.staff,
      );
    } on AppFailure {
      // Registered but the automatic sign-in failed (rare). They can sign
      // in from the Staff screen.
    }
    await setup.markReady();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Setup'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Register as Principal',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This school has no Principal yet. The first person to '
                'register here becomes the Principal. This can only be done '
                'once. After that, only you can add the other staff.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              AppTextField(
                controller: _nameController,
                label: 'Full Name',
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter your full name'
                    : null,
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
                    : const Text('Create Principal account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
