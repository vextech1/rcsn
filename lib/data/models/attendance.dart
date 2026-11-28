/// Attendance below this is a warning.
const double kAttendanceMinimum = 85;

/// One student's attendance in one course unit, as a percentage.
class Attendance {
  final String subjectId;
  final String subjectName;
  final int year;
  final int semester;
  final double percent;

  const Attendance({
    required this.subjectId,
    required this.subjectName,
    required this.year,
    required this.semester,
    required this.percent,
  });

  /// Null if [text] may be entered. Blank means not recorded.
  static String? errorFor(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final percent = RegExp(r'^\d{1,3}(\.\d)?$').hasMatch(value)
        ? double.parse(value)
        : null;
    return percent == null || percent > 100 ? '0 to 100' : null;
  }

  factory Attendance.fromMap(String subjectId, Map data) => Attendance(
        subjectId: subjectId,
        subjectName: data['subjectName'] as String,
        year: (data['year'] as num).toInt(),
        semester: (data['semester'] as num).toInt(),
        percent: (data['percent'] as num).toDouble(),
      );

  Map<String, Object> toMap() => {
        'subjectName': subjectName,
        'year': year,
        'semester': semester,
        'percent': percent,
      };

  bool get isLow => percent < kAttendanceMinimum;

  String get percentText => percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(1);

  /// Newest class first.
  static List<Attendance> sorted(List<Attendance> items) => [...items]
    ..sort((a, b) {
      if (a.year != b.year) return b.year - a.year;
      if (a.semester != b.semester) return b.semester - a.semester;
      return a.subjectName.compareTo(b.subjectName);
    });
}
