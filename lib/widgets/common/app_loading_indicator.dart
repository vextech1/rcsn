import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A themed loading indicator, used wherever a screen is waiting on a
/// stream or async call — AuthProvider.isResolving, StudentProvider.
/// isRestoring, an upload in progress, a Firestore stream's initial
/// connection state, and so on. Centralizing this means the loading
/// experience looks consistent everywhere rather than each screen using
/// Flutter's bare CircularProgressIndicator with no shared styling.
class AppLoadingIndicator extends StatelessWidget {
  final String? message;

  const AppLoadingIndicator({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: const TextStyle(color: AppColors.textMid)),
          ],
        ],
      ),
    );
  }
}
