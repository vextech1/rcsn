import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_size_formatter.dart';

/// A visible upload progress bar with byte-count context.
///
/// This is a direct, required implementation, not a nice-to-have: Section
/// 4.1 of the project document explicitly states that visible progress
/// and retry handling are "required — not optional — given the 100MB
/// cap," specifically because video uploads on weak mobile connections
/// are flagged as the app's highest-risk failure point. A silent spinner
/// or no feedback at all during a long upload is exactly the failure
/// mode that requirement exists to prevent.
///
/// [progress] is expected to come straight from ContentProvider.
/// uploadProgress (0.0 to 1.0) — this widget doesn't compute progress
/// itself, only displays it.
class UploadProgressIndicator extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final int totalBytes;
  final String fileName;
  final VoidCallback? onCancel;

  const UploadProgressIndicator({
    super.key,
    required this.progress,
    required this.totalBytes,
    required this.fileName,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final uploadedBytes = (totalBytes * progress).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (onCancel != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onCancel,
                  tooltip: 'Cancel upload',
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearPercentIndicator(
            percent: progress.clamp(0.0, 1.0),
            lineHeight: 8,
            progressColor: AppColors.primary,
            backgroundColor: const Color(0xFFE0E0E0),
            barRadius: const Radius.circular(4),
            padding: EdgeInsets.zero,
            animateFromLastPercent: true,
          ),
          const SizedBox(height: 6),
          Text(
            '${FileSizeFormatter.format(uploadedBytes)} of '
            '${FileSizeFormatter.format(totalBytes)} '
            '(${(progress * 100).toStringAsFixed(0)}%)',
            style: const TextStyle(fontSize: 12, color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}
