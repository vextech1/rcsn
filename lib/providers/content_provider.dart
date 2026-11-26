import 'dart:io';
import 'package:flutter/foundation.dart';
import '../data/repositories/content_repository.dart';
import '../data/models/content_item.dart';
import '../data/models/content_type_category.dart';
import '../core/errors/app_failure.dart';

/// Wraps ContentRepository's upload flow with UI-facing progress state.
///
/// [uploadProgress] exists specifically because Section 4.1 requires a
/// visible progress indicator for uploads at the 100MB cap — not
/// optional, per that section's note on weak connections. Screens bind directly
/// to this value rather than each screen managing its own progress
/// callback plumbing.
class ContentProvider extends ChangeNotifier {
  final ContentRepository _repository;

  ContentProvider({ContentRepository? repository})
      : _repository = repository ?? ContentRepository();

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  AppFailure? _lastError;

  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  AppFailure? get lastError => _lastError;

  Stream<List<ContentItem>> watchMainList(String subjectId) {
    return _repository.watchMainList(subjectId);
  }

  Stream<List<ContentItem>> watchArchive(String subjectId) {
    return _repository.watchArchive(subjectId);
  }

  Stream<List<ContentTypeCategory>> watchContentTypes() {
    return _repository.watchContentTypes();
  }

  /// Drives the upload flow end to end, updating [uploadProgress] as the
  /// repository/service layers report it. Resets progress to 0 at the
  /// start and leaves it at 1.0 briefly on success before the screen
  /// typically navigates away — screens shouldn't need to manually reset
  /// progress themselves between uploads, this method does it at the
  /// start of every call.
  Future<void> uploadContent({
    required String subjectId,
    required String tutorId,
    required String contentTypeId,
    required File file,
    required String fileName,
    required String fileExtension,
    required int fileSizeBytes,
    String? description,
  }) async {
    _isUploading = true;
    _uploadProgress = 0.0;
    _lastError = null;
    notifyListeners();

    try {
      await _repository.uploadContent(
        subjectId: subjectId,
        tutorId: tutorId,
        contentTypeId: contentTypeId,
        file: file,
        fileName: fileName,
        fileExtension: fileExtension,
        fileSizeBytes: fileSizeBytes,
        description: description,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );
    } on AppFailure catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Manual per-file archive (Section 4.2) — the only way this ever
  /// happens, triggered from a tutor's explicit tap on "Archive" in the
  /// file options menu. See ContentRepository's own doc comment for the
  /// stronger warning against ever calling this automatically.
  Future<void> archiveItem(String contentItemId) {
    return _repository.archiveItem(contentItemId);
  }

  Future<void> unarchiveItem(String contentItemId) {
    return _repository.unarchiveItem(contentItemId);
  }

  Future<void> updateDescription({
    required String contentItemId,
    required String description,
  }) {
    return _repository.updateDescription(
      contentItemId: contentItemId,
      description: description,
    );
  }

  Future<void> deleteItem({
    required String contentItemId,
    required String storagePath,
  }) {
    return _repository.deleteItem(
      contentItemId: contentItemId,
      storagePath: storagePath,
    );
  }

  /// ADMIN-ONLY per Section 4.3. Adds a new content-type category at
  /// runtime.
  Future<void> addContentType(String name) {
    return _repository.addContentType(name);
  }
}
