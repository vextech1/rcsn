import 'package:intl/intl.dart';

/// Whole Uganda shillings.
String formatUgx(int amount) =>
    'UGX ${NumberFormat.decimalPattern('en_US').format(amount)}';

/// Reads "1,500,000" or "1500000". Returns null for anything else. A leading
/// minus is accepted only when [allowNegative] is set.
int? parseUgx(String input, {bool allowNegative = false}) {
  final cleaned = input.replaceAll(RegExp(r'[,\s]'), '');
  if (!RegExp(r'^-?\d{1,10}$').hasMatch(cleaned)) return null;
  final value = int.parse(cleaned);
  if (value.abs() > 1000000000) return null;
  if (value < 0 && !allowNegative) return null;
  return value;
}
