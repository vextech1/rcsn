import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/storage_config.dart';
import '../../core/constants/upload_rules.dart';
import '../../core/errors/app_failure.dart';

/// Thin client for the file-storage Worker (Cloudflare R2). It validates,
/// uploads, downloads and deletes files.
///
/// The Worker decides who may do what: it checks the Firebase sign-in of a
/// staff member or tutor, or a student's NSIN for downloads. Checks made in
/// the app are only there to fail early.
class StorageService {
  final http.Client _client;
  final FirebaseAuth? _auth;
  final String _baseUrl;

  StorageService({
    http.Client? client,
    FirebaseAuth? auth,
    String baseUrl = StorageConfig.baseUrl,
  })  : _client = client ?? http.Client(),
        _auth = auth,
        _baseUrl = baseUrl;

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

  /// Uploads a file to [storagePath], reporting progress via [onProgress]
  /// (0.0 to 1.0). Returns the file's URL on the Worker.
  Future<String> uploadFile({
    required File file,
    required String storagePath,
    void Function(double progress)? onProgress,
  }) async {
    final uri = _uriFor(storagePath);
    try {
      final total = await file.length();
      final headers = await _headers();

      var sent = 0;
      final body = file.openRead().map((chunk) {
        sent += chunk.length;
        if (total > 0) onProgress?.call(sent / total);
        return chunk;
      });
      final request = _FileUpload(uri, body)
        ..contentLength = total
        ..headers.addAll(headers);

      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode != 201) {
        throw UploadFailedFailure(_errorFrom(response));
      }
      return uri.toString();
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw const UploadFailedFailure(
        'Upload failed. Check your connection and try again.',
      );
    }
  }

  /// Permanently removes a file. A file that is already gone counts as
  /// deleted. Archiving never calls this.
  Future<void> deleteFile(String storagePath) async {
    final uri = _uriFor(storagePath);
    try {
      final response = await _client.delete(uri, headers: await _headers());
      if (response.statusCode != 204) {
        throw UploadFailedFailure(_errorFrom(response));
      }
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw const UploadFailedFailure(
        'Could not delete the file. Check your connection and try again.',
      );
    }
  }

  /// Downloads a file to [localPath] (Section 2.3). Students have no sign-in,
  /// so they pass their [studentNsin] instead.
  Future<File> downloadForOffline({
    required String storagePath,
    required String localPath,
    String? studentNsin,
  }) async {
    final uri = _uriFor(storagePath);
    // Write to a temporary file so a broken download never replaces a good one.
    final partial = File('$localPath.part');
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(await _headers(studentNsin: studentNsin));
      final streamed = await _client.send(request);
      if (streamed.statusCode != 200) {
        throw DownloadFailedFailure(
          _errorFrom(await http.Response.fromStream(streamed)),
        );
      }
      await streamed.stream.pipe(partial.openWrite());
      return await partial.rename(localPath);
    } on AppFailure {
      rethrow;
    } catch (e) {
      if (await partial.exists()) await partial.delete();
      throw const DownloadFailedFailure(
        'Download failed. Check your connection and try again.',
      );
    }
  }

  Uri _uriFor(String storagePath) {
    if (_baseUrl.isEmpty) {
      throw const UploadFailedFailure(
        'File storage is not set up in this build.',
      );
    }
    final base = Uri.parse(_baseUrl);
    return base.replace(pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      'files',
      ...storagePath.split('/'),
    ]);
  }

  Future<Map<String, String>> _headers({String? studentNsin}) async {
    if (studentNsin != null) return {'X-Student-NSIN': studentNsin};
    final token =
        await (_auth ?? FirebaseAuth.instance).currentUser?.getIdToken();
    if (token == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  String? _errorFrom(http.Response response) {
    try {
      return (jsonDecode(response.body) as Map<String, dynamic>)['error']
          as String?;
    } catch (_) {
      return null;
    }
  }
}

/// A PUT whose body is streamed from disk, read only as fast as it is sent.
class _FileUpload extends http.BaseRequest {
  final Stream<List<int>> _body;

  _FileUpload(Uri url, this._body) : super('PUT', url);

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
