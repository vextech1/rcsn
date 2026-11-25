import 'package:flutter/material.dart';
import '../../core/errors/app_failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Renders an [AppFailure] directly, not a raw error string.
///
/// This is the payoff of the typed-failure hierarchy in
/// core/errors/app_failure.dart: because that file's whole purpose was
/// letting "the UI show specific messages instead of generic error
/// screens," this widget's job is simply to trust [failure.message] and
/// display it — the specificity was already decided at the point the
/// failure was thrown (e.g. NotAssignedFailure's exact wording), not
/// here. Screens should pass the actual typed failure object through
/// from a provider's lastError getter, not extract and pass a bare
/// String — keeping the type flowing all the way to display is what
/// keeps this consistent if a failure's message ever needs to change
/// (edit it once, in app_failure.dart, not in every screen that
/// happens to reference that error).
class AppErrorDisplay extends StatelessWidget {
  final AppFailure failure;
  final VoidCallback? onRetry;

  const AppErrorDisplay({
    super.key,
    required this.failure,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: AppTypography.body(context),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact, inline variant — for showing a failure beneath a form
/// field (e.g. NSIN entry, login) rather than taking over the whole
/// screen the way [AppErrorDisplay] does. Used where a full-screen error
/// state would be wrong (the person is still mid-form, not navigating
/// away from broken content).
class AppInlineError extends StatelessWidget {
  final AppFailure failure;

  const AppInlineError({super.key, required this.failure});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              failure.message,
              style: AppTypography.caption(context).copyWith(
                    color: AppColors.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
