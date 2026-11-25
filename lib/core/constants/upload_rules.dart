/// File upload rules, per Section 4.1 of the project document.
///
/// Allowed types: image, PDF, Excel, Word, video. Audio is explicitly
/// excluded — not an oversight, a deliberate scope decision.
class UploadRules {
  UploadRules._(); // static-only, never instantiated

  /// 100MB cap, set deliberately generous enough to fit large reference
  /// documents (e.g. a Ross & Wilson Anatomy PDF, commonly ~50MB) without
  /// forcing chunked uploads.
  static const int maxFileSizeBytes = 100 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    // Images
    'jpg', 'jpeg', 'png', 'heic',
    // Documents
    'pdf', 'doc', 'docx', 'xls', 'xlsx',
    // Video
    'mp4', 'mov', 'avi', 'mkv',
  ];

  /// Extensions that trigger client-side compression before upload.
  /// Video is the highest-risk upload type at this file-size ceiling on
  /// weak mobile connections — compression is required, not optional,
  /// per Section 4.1's explicit note.
  static const List<String> videoExtensionsRequiringCompression = [
    'mp4', 'mov', 'avi', 'mkv',
  ];

  static bool isExtensionAllowed(String extension) {
    return allowedExtensions.contains(extension.toLowerCase().replaceAll('.', ''));
  }

  static bool requiresCompression(String extension) {
    return videoExtensionsRequiringCompression
        .contains(extension.toLowerCase().replaceAll('.', ''));
  }

  static bool isWithinSizeLimit(int sizeInBytes) {
    return sizeInBytes <= maxFileSizeBytes;
  }

  /// Human-readable cap for display in upload-rejection messages.
  static const String maxFileSizeLabel = '100MB';
}
