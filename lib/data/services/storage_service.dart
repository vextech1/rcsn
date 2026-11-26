import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/constants/upload_rules.dart';
import '../../core/errors/app_failure.dart';

/// Thin wrapper around Firebase Storage. Deliberately has NO knowledge of
/// subjects, tutors, or assignments — it only knows how to validate,
/// upload, and delete files against the raw rules in [UploadRules].
/// Whether a given tutor is ALLOWED to upload into a given subject is a
/// permission check that belongs in a repository, not here — this class
/// would happily upload a file to any path it's given. Keeping that
/// judgment out of this layer is deliberate, not an omission.
class StorageService {
  final FirebaseStorage _storage;

  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Validates a file against [UploadRules] BEFORE any network call is
  /// made. This is a fast, local, offline-capable check — no reason to
  /// spend a student or tutor's mobile data attempting an upload that
  /// will be rejected anyway.
  ///
  /// Throws [FileTooLargeFailure] or [UnsupportedFileTypeFailure] rather
  /// than returning a bool, so callers can catch the specific failure type
  /// and show the exact right message (per core/errors/app_failure.dart's
  /// whole reason for existing).
  void validateBeforeUpload({
    required int fileSizeBytes,
    required String fileExtension,
  }) {
    if (!UploadRules.isExtensionAllowed(fileExtension)) {
      throw const UnsupportedFileTypeFailure();
    }
    if (!UploadRules.isWithinSizeLimit(fileSizeBytes)) {
      throw const FileTooLargeFailure();
    }
  }

  /// Uploads a file to the given storage path, reporting progress via
  /// [onProgress] (0.0 to 1.0) so the UI can drive the progress indicator
  /// that Section 4.1 explicitly requires for uploads at this file-size
  /// ceiling — not optional, per that section's note on weak connections.
  ///
  /// [storagePath] is built by the caller (repository layer), typically
  /// something like `subjects/{subjectId}/content/{contentItemId}.{ext}` —
  /// this service doesn't decide path structure, just executes the upload.
  Future<String> uploadFile({
    required File file,
    required String storagePath,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final ref = _storage.ref(storagePath);
      final uploadTask = ref.putFile(file);

      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes > 0) {
            onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
          }
        });
      }

      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw UploadFailedFailure(e.message);
    }
  }

  /// Deletes a file from Storage. Used by the tutor's "Delete" file-option
  /// action (Section 4.2) — note this is different from Archive, which
  /// never touches Storage, only flips [ContentItem.isArchived] in
  /// Firestore. Deletion here is permanent removal of the underlying file.
  Future<void> deleteFile(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (e) {
      // Treat "already gone" as success, not failure — deleting something
      // that's already deleted shouldn't surface as an error to the tutor.
      if (e.code == 'object-not-found') return;
      throw UploadFailedFailure(e.message);
    }
  }

  /// Downloads a file to local storage for offline viewing (Section 2.3).
  /// [localPath] is provided by the caller — typically built via
  /// path_provider against the app's documents directory.
  Future<File> downloadForOffline({
    required String storagePath,
    required String localPath,
  }) async {
    try {
      final file = File(localPath);
      await _storage.ref(storagePath).writeToFile(file);
      return file;
    } on FirebaseException catch (e) {
      throw UploadFailedFailure(e.message);
    }
  }
}
