import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Tutor login. Shares [AuthProvider.signIn] with the staff login (same
/// email + password method). It signs in through [LoginDoor.tutor], so a
/// staff account entered here is rejected by AuthProvider instead of being
/// accepted and sent to a staff dashboard.
class TutorLoginScreen extends StatefulWidget {
  const TutorLoginScreen({super.key});

  @override
  State<TutorLoginScreen> createState() => _TutorLoginScreenState();
}

class _TutorLoginScreenState extends State<TutorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  AppFailure? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await context.read<AuthProvider>().signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            door: LoginDoor.tutor,
          );
      // Same reasoning as TutorRegisterScreen: no manual navigation.
      // The router's redirect guard sends a resolved Tutor session to
      // TutorDashboard (or tutorAccountInactive, if suspended) on its
      // own once AuthProvider resolves the role.
    } on AppFailure catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Also watch AuthProvider: a staff account entered here is rejected
    // after sign-in, during role resolution, and that message reaches
    // AuthProvider.lastError rather than anything signIn() throws.
    final auth = context.watch<AuthProvider>();
    final error = _error ?? auth.lastError;
    final isBusy = _isSubmitting || auth.isResolving;

    return Scaffold(
      appBar: AppBar(title: const Text('Tutor Login')),
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
              const SizedBox(height: 12),
              TextButton(
                onPressed: isBusy
                    ? null
                    : () => context.go(AppRoutes.tutorRegister),
                child: const Text("Don't have an account? Register"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
