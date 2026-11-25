/// Validation for NSIN (National Student Identification Number) input.
///
/// NSIN is the school's admission identifier — per Section 2.3, it's a
/// student's only means of entering the app, so validating the *format*
/// client-side (before ever hitting Firestore) gives faster, clearer
/// feedback than a network round-trip for an obviously malformed entry.
/// This does NOT check whether the NSIN actually exists — that's a
/// repository/Firestore lookup, not a format check.
///
/// Confirmed real-world format, from an actual former-student example:
///
///   JAN21/U028/CCN/002
///   └─┬─┘ └┬─┘ └┬┘ └┬┘
///     │    │    │   └─ sequence number within that class (alphabetical)
///     │    │    └───── course code
///     │    └────────── fixed RCSN school number (matches U028 on rcsn.info)
///     └─────────────── intake month + 2-digit year
///
/// RCSN confirmed 2 intakes per year, so the month segment can legitimately
/// be any month abbreviation — NOT limited to January.
///
/// Course codes are intentionally NOT validated against a closed list.
/// "CCN" in the example above was for a since-discontinued course and must
/// not be hardcoded as one of the six current tracks — doing so would
/// silently reject real NSINs from any track whose actual code differs
/// from a guess. The course-code segment is checked only for
/// plausible shape (letters, roughly course-code length), not content,
/// until RCSN confirms the real code for all six current tracks
/// (Section 3.1). Update [_fullPattern]'s course-code group once that
/// list exists.
class NsinValidator {
  NsinValidator._();

  /// Fixed school number — confirmed against rcsn.info's own BTVET/UNMC
  /// registration reference, and matches the real example NSIN exactly.
  /// Not expected to ever change, but pulled out as a named constant
  /// rather than buried in a regex literal, in case RCSN registers a
  /// second school number for a future campus.
  static const String schoolNumber = 'U028';

  // MONTH: 3-letter month abbreviation (any month — 2 intakes/year, not just Jan)
  // YEAR: 2 digits
  // SCHOOL: fixed U028
  // COURSE: 2-4 letters, placeholder shape check only — see class doc above
  // SEQ: 2-4 digits
  static final RegExp _fullPattern = RegExp(
    r'^[A-Z]{3}\d{2}/' // month + year, e.g. JAN21
    r'U028/' // fixed school number
    r'[A-Z]{2,4}/' // course code — shape only, not a closed list
    r'\d{2,4}$', // sequence number
    caseSensitive: false,
  );

  static bool isValidFormat(String input) {
    return _fullPattern.hasMatch(input.trim());
  }

  /// Normalizes input before lookup — trims whitespace and uppercases,
  /// since the confirmed format is uppercase (JAN21/U028/CCN/002) and
  /// Firestore document IDs/fields built from this should be consistent
  /// regardless of how the student typed it.
  static String normalize(String input) {
    return input.trim().toUpperCase();
  }

  static String? errorMessage(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Please enter your NSIN.';
    if (!isValidFormat(trimmed)) {
      return 'That doesn\'t look like a valid NSIN. '
          'Expected format: MONYY/$schoolNumber/COURSE/NNN '
          '(e.g. JAN21/$schoolNumber/CCN/002)';
    }
    return null;
  }
}
