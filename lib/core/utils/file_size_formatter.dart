/// Formats a byte count into a human-readable size string, used wherever
/// file size is shown to the user — upload previews, the 100MB-limit
/// rejection message, file list items.
class FileSizeFormatter {
  FileSizeFormatter._();

  static String format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
