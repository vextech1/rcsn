/// Student numbers and the formats the Academic Registrar sets for them.
///
/// In a format, `#` stands for a digit, `@` for a letter and `*` for either.
/// Everything else must be typed as it is. For example `@@@##/U028/@@@/###`
/// accepts `JAN21/U028/CCN/002`. A number is accepted if it fits any one of
/// the formats. With no format set, any well-formed number is accepted.
///
/// The database still calls the field `nsin`.
class StudentNumber {
  StudentNumber._();

  static const int maxFormats = 5;

  /// Upper case with no surrounding spaces.
  static String normalize(String input) => input.trim().toUpperCase();

  /// What every student number must satisfy, whatever the format. The
  /// Firestore rules require the same.
  static final RegExp _wellFormed = RegExp(r'^[A-Z0-9][A-Z0-9/.\-]{2,29}$');

  static final RegExp _formatShape =
      RegExp(r'^[A-Z0-9#@*][A-Z0-9/.\-#@*]{2,29}$');

  static String? basicError(String input) {
    final value = normalize(input);
    if (value.isEmpty) return 'Please enter the student number.';
    if (!_wellFormed.hasMatch(value)) {
      return 'A student number is 3 to 30 letters and digits, which may '
          'include / . or - but no spaces.';
    }
    return null;
  }

  /// Null if [format] can be saved.
  static String? formatError(String format) =>
      _formatShape.hasMatch(normalize(format))
          ? null
          : 'Use 3 to 30 characters: letters, digits, / . - and the symbols '
              '# @ *';

  static bool matches(String input, String format) {
    final pattern = normalize(format).split('').map((c) {
      switch (c) {
        case '#':
          return '[0-9]';
        case '@':
          return '[A-Z]';
        case '*':
          return '[A-Z0-9]';
        default:
          return RegExp.escape(c);
      }
    }).join();
    return RegExp('^$pattern\$').hasMatch(normalize(input));
  }

  /// Null if [input] is acceptable under [formats].
  static String? errorFor(String input, List<String> formats) {
    final basic = basicError(input);
    if (basic != null) return basic;
    if (formats.isEmpty || formats.any((f) => matches(input, f))) return null;
    return 'That student number is not in the school\'s format: '
        '${formats.join(' or ')} (# digit, @ letter, * either).';
  }

  /// The document id for a student's bio data. Payment codes never contain
  /// `_`, so the two kinds of id cannot collide.
  static String bioKey(String number) => number.contains('/')
      ? number.replaceAll('/', '_')
      : 'N_$number';
}
