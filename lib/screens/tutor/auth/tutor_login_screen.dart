import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Tutor login. Shares [AuthProvider.signIn] with Admin login (once that
/// screen exists) — the same method per Section 2.4's permission table
/// showing both roles use email+password, and role resolution after
/// sign-in is AuthProvider's job (checking AdminRepository then
/// TutorRepository), not something this screen decides.
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
                    : const Text('Log In'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSubmitting
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
