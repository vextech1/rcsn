import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/common/app_error_display.dart';

/// Student settings — the one place a student can view their full NSIN
/// and clear their session.
///
/// CLEAR SESSION is the borrowed-phone solution described in
/// [StudentProvider]'s doc comment. Because the NSIN is persisted in
/// shared_preferences, a student who borrows someone else's phone would
/// see the phone owner's data. Clear Session removes the persisted NSIN
/// and returns to the NSIN entry screen so the borrower can enter their
/// own.
///
/// Per the product decision referenced in [StudentProvider]: this action
/// lives in Settings only (not surfaced on the dashboard), and requires
/// confirmation before clearing. Both choices protect a student's own
/// long-running session from accidental clearing — the trade-off is that
/// a borrower has to actively find this screen.
class StudentSettingsScreen extends StatelessWidget {
  const StudentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>().currentStudent;

    if (student == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const AppErrorDisplay(
          failure: UnknownFailure('No active student session.'),
        ),
      );
    }

    final trackLabel = kTrackDefinitions[student.programType]?.label ??
        student.programType.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Student identity
          _SectionLabel(text: 'Account'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.name, style: AppTypography.heading3(context)),
                  const SizedBox(height: 4),
                  Text(trackLabel, style: AppTypography.bodyMuted(context)),
                  Text(
                    'Year ${student.year} · Semester ${student.semester}',
                    style: AppTypography.caption(context),
                  ),
                  const Divider(height: 24),
                  _InfoRow(label: 'NSIN', value: student.nsin),
                  _InfoRow(
                    label: 'Status',
                    value: student.status.name,
                    valueColor: student.isActive ? AppColors.success : AppColors.error,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Clear session — the borrowed-phone solution
          _SectionLabel(text: 'Session'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clear Session',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  // Was `const Text(...)` — const removed, same
                  // reasoning as StudentSearchScreen's equivalent fix:
                  // AppTypography.caption(context) is a runtime call,
                  // incompatible with const regardless of what's passed.
                  Text(
                    'Removes your NSIN from this device. Use this if '
                    'you are borrowing someone else\'s phone, or before '
                    'handing your phone to another student. You will '
                    'return to the NSIN entry screen afterward.',
                    style: AppTypography.caption(context),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    icon: const Icon(Icons.exit_to_app, size: 18),
                    label: const Text('Clear Session'),
                    onPressed: () => _confirmClearSession(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearSession(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear your session?'),
        content: const Text(
          'Your NSIN will be removed from this device. You will need '
          'to enter it again to access your academic information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await context.read<StudentProvider>().clearSession();
    // Router guard sees the session is now null and redirects to
    // studentSearch automatically — no manual navigation needed.
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMid,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: AppTypography.caption(context)),
          ),
          Expanded(
            child: Text(
              value,
              // Was `AppTypography.body.copyWith(colorScheme:
              // ColorScheme(surface: valueColor))` — TextStyle.copyWith
              // has no colorScheme parameter at all; it takes a plain
              // color: parameter directly. This was the same broken
              // pattern found and removed from app_theme.dart's old
              // textTheme block — a misunderstanding of TextStyle's real
              // API, not a legitimate way to override color. valueColor
              // is already the correct type (Color?) for this simple
              // form; copyWith accepts a nullable color and leaves the
              // base style's color untouched when null is passed, which
              // is exactly the desired "only override when valueColor is
              // actually provided" behavior _InfoRow's optional
              // valueColor parameter implies.
              style: AppTypography.body(context).copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
