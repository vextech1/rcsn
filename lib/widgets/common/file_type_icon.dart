import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Maps a file extension to an appropriate icon and color.
///
/// Covers exactly the extensions [UploadRules.allowedExtensions] permits
/// (core/constants/upload_rules.dart) — image, PDF, Excel, Word.
/// If this list and that one ever drift apart (a new extension gets
/// allowed for upload but has no icon mapping here), the default case
/// below renders a generic file icon rather than crashing — but that
/// drift itself would be worth catching, so extending
/// UploadRules.allowedExtensions should come with a matching addition
/// here.
class FileTypeIcon extends StatelessWidget {
  final String fileExtension;
  final double size;

  const FileTypeIcon({
    super.key,
    required this.fileExtension,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final ext = fileExtension.toLowerCase().replaceAll('.', '');
    final iconData = _iconFor(ext);
    return Icon(iconData.$1, size: size, color: iconData.$2);
  }

  (IconData, Color) _iconFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'heic':
        return (Icons.image, AppColors.accent);
      case 'pdf':
        return (Icons.picture_as_pdf, AppColors.error);
      case 'doc':
      case 'docx':
        return (Icons.description, AppColors.primary);
      case 'xls':
      case 'xlsx':
        return (Icons.table_chart, AppColors.secondary);
      default:
        return (Icons.insert_drive_file, AppColors.textMid);
    }
  }
}
