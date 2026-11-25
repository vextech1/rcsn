import 'dart:io';
import 'package:video_compress/video_compress.dart';
import '../../core/constants/upload_rules.dart';
import '../../core/errors/app_failure.dart';

/// Handles client-side video compression before upload.
///
/// Kept as its own service rather than folded into [StorageService]
/// deliberately: Section 4.1 of the project document flags video as "the
/// one part of this app most likely to fail silently on weak data
/// connections" and states compression is REQUIRED, not optional, at the
/// 100MB cap. Giving it a dedicated service — rather than a private
/// helper method buried inside the upload flow — makes that requirement
/// structurally visible: any upload path for a video file must call
/// through here first, and skipping it should look like an obvious
/// missing step in the calling code, not an easy-to-overlook branch.
class VideoCompressionService {
  /// Compresses a video file if its extension requires it
  /// (per [UploadRules.requiresCompression]). Returns the original file
  /// unchanged if compression isn't applicable (e.g. it's an image).
  ///
  /// Reports progress via [onProgress] (0.0 to 1.0) — compression on a
  /// weak device can itself take real time, and per Section 4.1's
  /// requirement for visible progress on large uploads, the same
  /// expectation applies here: no silent multi-minute wait.
  Future<File> compressIfNeeded({
    required File file,
    required String fileExtension,
    void Function(double progress)? onProgress,
  }) async {
    if (!UploadRules.requiresCompression(fileExtension)) {
      return file;
    }

    try {
      final subscription = onProgress == null
          ? null
          : VideoCompress.compressProgress$.subscribe((progress) {
              onProgress(progress / 100);
            });

      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: false, // audio is explicitly out of scope — Section 4.1
      );

      subscription?.unsubscribe();

      if (info == null || info.file == null) {
        throw const CompressionFailedFailure();
      }

      return info.file!;
    } catch (e) {
      if (e is CompressionFailedFailure) rethrow;
      throw const CompressionFailedFailure();
    }
  }

  /// Cancels an in-progress compression — used if the tutor backs out of
  /// an upload mid-compression.
  Future<void> cancel() async {
    await VideoCompress.cancelCompression();
  }
}
