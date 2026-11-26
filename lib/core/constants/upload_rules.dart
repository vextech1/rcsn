/// File upload rules, per Section 4.1 of the project document.
///
/// Allowed types: image, PDF, Excel, Word. Audio and video are explicitly
/// excluded — not an oversight, a deliberate scope decision.
class UploadRules {
  UploadRules._(); // static-only, never instantiated

  /// 95 MB cap (Cloudflare rejects requests over 100 MB; keep in step with
  /// worker/src/index.js), set deliberately generous enough to fit large reference
  /// documents (e.g. a Ross & Wilson Anatomy PDF, commonly ~50MB) without
  /// forcing chunked uploads.
  static const int maxFileSizeBytes = 95 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    // Images
    'jpg', 'jpeg', 'png', 'heic',
    // Documents
    'pdf', 'doc', 'docx', 'xls', 'xlsx',
  ];

  static bool isExtensionAllowed(String extension) {
    return allowedExtensions.contains(extension.toLowerCase().replaceAll('.', ''));
  }

  static bool isWithinSizeLimit(int sizeInBytes) {
    return sizeInBytes <= maxFileSizeBytes;
  }

  /// Human-readable cap for display in upload-rejection messages.
  static const String maxFileSizeLabel = '95 MB';
}
