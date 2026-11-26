import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/nsin_validator.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/app_text_field.dart';

/// The student entry point — NSIN-only, no password (Section 2.3).
///
/// A student enters their National Student Identification Number to
/// access the app. There is no registration and no Firebase Auth
/// involved — the NSIN IS the access mechanism. The lookup is a
/// Firestore exact-match query against the `students` collection.
///
/// PERSISTED SESSION: on first launch, [StudentProvider.isRestoring] is
/// true while a previously-saved NSIN is re-resolved from
/// shared_preferences. This screen shows a loading state during that
/// window to avoid a flash of the input form before a valid persisted
/// session loads. If the persisted session resolves to a usable student,
/// the router guard redirects to the dashboard — this screen never
/// renders the form in that case.
///
/// After submission, this screen does NOT navigate manually. The router
/// guard's `refreshListenable` reacts to [StudentProvider]'s state
/// change and redirects to the dashboard (or account-inactive) on its
/// own — same pattern as TutorRegisterScreen / TutorLoginScreen.
class StudentSearchScreen extends StatefulWidget {
  const StudentSearchScreen({super.key});

  @override
  State<StudentSearchScreen> createState() => _StudentSearchScreenState();
}

class _StudentSearchScreenState extends State<StudentSearchScreen> {
  final _nsinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nsinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await context
        .read<StudentProvider>()
        .searchByNsin(_nsinController.text);
    // No manual navigation — router guard reacts to provider state
    // change via refreshListenable. Same pattern as tutor auth screens.
  }

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>();

    // While the provider is checking shared_preferences for a
    // previously-saved NSIN, show a loading state rather than the
    // input form — avoids a flash of the form before a persisted
    // session loads and the router redirects away.
    if (student.isRestoring) {
      return const Scaffold(
        body: AppLoadingIndicator(message: 'Loading…'),
      );
    }

    // Edge case: router guard would normally redirect before this
    // screen renders, but if it somehow didn't, show a loading state
    // rather than a confusing input form for an already-signed-in user.
    if (student.isUsableSession) {
      return const Scaffold(
        body: AppLoadingIndicator(message: 'Loading your account…'),
      );
    }

    final lastError = student.lastError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RCSN Student Access'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // Crest placeholder — same pattern as WelcomeScreen.
              // Replace with Image.asset once the crest file is in
              // assets/images/.
              const Icon(
                Icons.local_hospital,
                size: 72,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),

              Text(
                'Enter your NSIN to continue',
                textAlign: TextAlign.center,
                style: AppTypography.heading3(context),
              ),
              const SizedBox(height: 8),
              // Was `const Text(...)` — removed const here, not just
              // added (context) to the style. A const widget requires
              // every value, including style:, to be knowable at compile
              // time; AppTypography.bodyMuted(context) is a runtime call
              // (it reads Theme.of(context) internally for dark-mode-
              // correct color), so this widget can no longer be const at
              // all, regardless of what's passed to style.
              Text(
                'Your National Student Identification Number was given '
                'to you at admission. If you don\'t know it, contact '
                'the school administration.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMuted(context),
              ),

              const SizedBox(height: 32),

              // NSIN input field — validates format client-side via
              // NsinValidator before any network call.
              AppTextField(
                controller: _nsinController,
                label: 'NSIN',
                keyboardType: TextInputType.text,
                validator: (value) => NsinValidator.errorMessage(
                  value ?? '',
                ),
                error: lastError,
              ),

              const SizedBox(height: 24),

              // Submit button — disabled while a Firestore lookup is
              // in flight. The provider's isSearching flag gates this.
              FilledButton.icon(
                onPressed: student.isSearching ? null : _submit,
                icon: student.isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: const Text('Look Up'),
              ),

              const SizedBox(height: 12),

              // Back to role selection — for a student who tapped
              // "Student" by mistake and wants to go back.
              //
              // This screen is not always pushed on top of role selection:
              // after Clear Session (or an inactive account) the router
              // redirects here and this is the ONLY page in the stack.
              // Popping the last page leaves an empty Navigator = black
              // screen, so go to role selection when there is nothing to
              // pop back to.
              TextButton(
                onPressed: student.isSearching
                    ? null
                    : () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.roleSelect),
                child: const Text('← Back to role selection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
