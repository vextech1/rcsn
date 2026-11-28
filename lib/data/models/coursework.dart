/// One of the five marks that make up a course unit's coursework.
class CourseworkPart {
  final String key;
  final String label;
  final String shortLabel;
  final int max;

  const CourseworkPart(this.key, this.label, this.shortLabel, this.max);
}

/// The coursework weights used across Uganda. They add up to
/// [kCourseworkMax]; firestore.rules enforce the same limits.
const List<CourseworkPart> kCourseworkParts = [
  CourseworkPart('practical', 'Practicals and projects', 'Practicals', 10),
  CourseworkPart('assignments', 'Exercises and assignments', 'Assignments', 5),
  CourseworkPart('tests', 'Class tests', 'Tests', 5),
  CourseworkPart('clinical', 'Clinical assessment', 'Clinical', 10),
  CourseworkPart('recordBook', 'Clinical record book', 'Record book', 10),
];

const int kCourseworkMax = 40;

/// Half of [kCourseworkMax]. A complete total below this is a retake.
const int kCourseworkPass = 20;

/// The marks entered so far, by [CourseworkPart.key].
class CourseworkMarks {
  final Map<String, double> values;

  const CourseworkMarks([this.values = const {}]);

  factory CourseworkMarks.fromMap(Object? data) {
    final map = data is Map ? data : const {};
    return CourseworkMarks({
      for (final part in kCourseworkParts)
        if (map[part.key] is num) part.key: (map[part.key] as num).toDouble(),
    });
  }

  /// Null if [text] may be entered for [part]. Blank means not yet marked.
  static String? errorFor(CourseworkPart part, String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final mark = RegExp(r'^\d{1,2}(\.\d)?$').hasMatch(value)
        ? double.parse(value)
        : null;
    return mark == null || mark > part.max ? '0 to ${part.max}' : null;
  }

  static String format(double mark) => mark == mark.roundToDouble()
      ? mark.toStringAsFixed(0)
      : mark.toStringAsFixed(1);

  bool get isEmpty => values.isEmpty;

  bool get isComplete =>
      kCourseworkParts.every((part) => values.containsKey(part.key));

  /// Rounded to one decimal, so that adding decimals cannot turn a 20 into
  /// 19.999.
  double get total =>
      (values.values.fold<double>(0, (a, b) => a + b) * 10).round() / 10;

  /// Only once all five marks are in, so an unfinished entry is not flagged.
  bool get isRetake => isComplete && total < kCourseworkPass;

  bool sameAs(CourseworkMarks other) =>
      kCourseworkParts.every((p) => values[p.key] == other.values[p.key]);
}

/// One student's coursework in one course unit, as the Registrar holds it.
class CourseworkEntry {
  final String nsin;
  final String subjectId;
  final String subjectName;
  final String programType;
  final int year;
  final int semester;
  final CourseworkMarks marks;

  /// The student can see a version of this result.
  final bool published;

  /// Saved since it was published, so the student still sees the old marks.
  final bool pendingChanges;

  const CourseworkEntry({
    required this.nsin,
    required this.subjectId,
    required this.subjectName,
    required this.programType,
    required this.year,
    required this.semester,
    required this.marks,
    this.published = false,
    this.pendingChanges = false,
  });

  factory CourseworkEntry.fromMap(Map<String, dynamic> data) =>
      CourseworkEntry(
        nsin: data['nsin'] as String,
        subjectId: data['subjectId'] as String,
        subjectName: data['subjectName'] as String,
        programType: data['programType'] as String,
        year: data['year'] as int,
        semester: data['semester'] as int,
        marks: CourseworkMarks.fromMap(data['marks']),
        published: data['published'] == true,
        pendingChanges: data['pendingChanges'] == true,
      );

  CourseworkEntry copyWith({
    CourseworkMarks? marks,
    bool? published,
    bool? pendingChanges,
  }) =>
      CourseworkEntry(
        nsin: nsin,
        subjectId: subjectId,
        subjectName: subjectName,
        programType: programType,
        year: year,
        semester: semester,
        marks: marks ?? this.marks,
        published: published ?? this.published,
        pendingChanges: pendingChanges ?? this.pendingChanges,
      );

  String get statusLabel => !published
      ? 'Draft'
      : pendingChanges
          ? 'Published, changes not yet published'
          : 'Published';
}
