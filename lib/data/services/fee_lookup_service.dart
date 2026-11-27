import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/storage_config.dart';
import '../../core/errors/app_failure.dart';
import '../models/fee_view.dart';
import '../models/student_fee.dart';

/// Asks the Worker for a student's fees. The Worker does the checking; the
/// app cannot read fee records itself. Nothing is saved on the phone.
class FeeLookupService {
  final http.Client _client;
  final String _baseUrl;

  FeeLookupService({http.Client? client, String baseUrl = StorageConfig.baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl;

  /// A signed-in student types only the payment code. Their NSIN goes with it
  /// from the session.
  Future<List<FeeView>> forStudent(String code, String nsin) =>
      _ask({'code': StudentFee.normalizeNumber(code), 'nsin': nsin});

  /// Parents, guardians and students without an NSIN.
  Future<List<FeeView>> withAnswers(
    String code,
    String guardian,
    Map<FeeQuestion, String> answers,
  ) =>
      _ask({
        'code': StudentFee.normalizeNumber(code),
        'guardian': guardian.trim(),
        'answers': {
          for (final entry in answers.entries)
            entry.key.name: entry.value.trim(),
        },
      });

  Future<List<FeeView>> _ask(Map<String, Object> body) async {
    if (_baseUrl.isEmpty) {
      throw const FeeFailure('Fee lookup is not set up in this build.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/fees'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw FeeFailure(
          data['error'] as String? ?? 'Could not load the fees. Try again.',
        );
      }
      return [
        for (final record in data['records'] as List)
          FeeView.fromJson(record as Map<String, dynamic>),
      ];
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const FeeFailure(
        'Could not load the fees. Check your connection and try again.',
      );
    }
  }
}
