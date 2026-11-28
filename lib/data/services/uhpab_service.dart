import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/storage_config.dart';
import '../../core/errors/app_failure.dart';
import '../models/uhpab.dart';

/// Asks the Worker for a student's published UHPAB results. The Worker applies
/// the fee block; the app cannot read the records itself.
class UhpabService {
  final http.Client _client;
  final String _baseUrl;

  UhpabService({http.Client? client, String baseUrl = StorageConfig.baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl;

  Future<UhpabResults> forStudent(String nsin) async {
    if (_baseUrl.isEmpty) {
      throw const CourseworkFailure(
        'UHPAB results are not set up in this build.',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse('${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/uhpab'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'nsin': nsin}),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw CourseworkFailure(
          data['error'] as String? ?? 'Could not load your results.',
        );
      }
      return UhpabResults.fromWorker(data);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const CourseworkFailure(
        'Could not load your results. Check your connection and try again.',
      );
    }
  }
}
