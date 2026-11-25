import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Tutor self-registration — Section 2.2: a tutor registers themselves
/// (name/email/password), no Admin bottleneck to get an account. This
/// is deliberately NOT the same as Admin setup: any number of tutors can
/// register, unlike the exactly-one-Admin rule.
///
/// WHAT THIS SCREEN DOES NOT DO: assign the new tutor to any
/// subject/class. Per the locked-in permission model (Section 2.2,
/// after the self-assign proposal was raised and explicitly reverted),
/// only Admin assigns tutors to subjects — see AdminTutorsScreen. A
/// freshly-registered tutor lands on TutorDashboard in the
/// "Not yet assigned, contact Admin" empty state (Section 5 step 5),
/// not a class-picker here.
///
/// This is the first screen in the project to actually exercise the
/// AuthProvider wiring added to main.dart — `context.read<AuthProvider>()`
/// would have thrown ProviderNotFoundException before that batch existed.
class TutorRegisterScreen extends StatefulWidget {
  const TutorRegisterScreen({super.key});

  @override
  State<TutorRegisterScreen> createState() => _TutorRegisterScreenState();
}

class _TutorRegisterScreenState extends State<TutorRegisterScreen> {
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
      await context.read<AuthProvider>().registerTutor(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // No manual navigation here — the router's redirect guard picks
      // up the new session the moment AuthProvider's authStateChanges
      // listener resolves the role (see app_router.dart's
      // refreshListenable), and lands on TutorDashboard on its own.
      // Navigating manually here would race that guard.
    } on AppFailure catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutor Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create your tutor account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'After registering, an Admin will assign you to the '
                'subjects and classes you teach.',
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
                    : const Text('Register'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => context.go(AppRoutes.tutorLogin),
                child: const Text('Already have an account? Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
