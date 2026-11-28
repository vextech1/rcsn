import '../../core/constants/academic_structure.dart';
import 'coursework.dart';
import 'student_record.dart';
import 'uhpab.dart';

/// The wording printed on every result slip and transcript. The Registrar can
/// change all of it; [defaults] only fills it the first time.
class DocumentTemplate {
  final Map<String, String> values;

  const DocumentTemplate(this.values);

  /// Field keys and what each is called, in the order shown.
  static const Map<String, String> labels = {
    'schoolName': 'School name',
    'address': 'Address',
    'contact': 'Telephone, email and website',
    'accreditation': 'Accreditation',
    'slipTitle': 'Result slip title',
    'transcriptTitle': 'Transcript title',
    'signatory1': 'First signature line',
    'signatory2': 'Second signature line',
    'footer': 'Note at the bottom',
  };

  /// The limit on each field. The rules check the same.
  static const int maxLength = 200;

  /// Name, town, website and accreditation as published on www.rcsn.ac.ug.
  static const DocumentTemplate defaults = DocumentTemplate({
    'schoolName': 'Rakai Community School of Nursing',
    'address': 'Rakai Town Council, Rakai, Uganda',
    'contact': 'www.rcsn.ac.ug',
    'accreditation': 'Accredited by MoES (ME/VOC/071) and UNMC. '
        'UHPAB Assessment Center U151.',
    'slipTitle': 'Semester Result Slip',
    'transcriptTitle': 'Academic Transcript',
    'signatory1': 'Academic Registrar',
    'signatory2': 'Principal',
    'footer': 'Not valid without the signatures and the school stamp.',
  });

  /// Saved values over the defaults. A field saved as blank stays blank.
  factory DocumentTemplate.fromMap(Map<String, dynamic>? data) =>
      DocumentTemplate({
        for (final key in labels.keys)
          key: data?[key] is String
              ? data![key] as String
              : defaults.values[key]!,
      });

  String operator [](String key) => values[key] ?? '';
}

/// One course unit's line. Every cell is text, so that it can be corrected.
class ResultRow {
  String unit;
  String coursework;
  String uhpab;
  String grade;
  String points;

  ResultRow({
    this.unit = '',
    this.coursework = '',
    this.uhpab = '',
    this.grade = '',
    this.points = '',
  });
}

/// One semester's table.
class ResultSection {
  String heading;
  final List<ResultRow> rows;

  /// For example `GPA: 3.50`. Left out of the page when blank.
  String summary;

  ResultSection({required this.heading, required this.rows, this.summary = ''});
}

/// A `label: value` line about the student. Left out when the value is blank.
class ResultDetail {
  String label;
  String value;

  ResultDetail(this.label, this.value);
}

/// A result slip or transcript as it will be printed. It starts from the
/// student's published results and the school's template, and any part of it
/// can then be edited. Editing it changes no record.
class ResultDocument {
  final Map<String, String> wording;
  String title;
  final List<ResultDetail> details;
  final List<ResultSection> sections;

  ResultDocument({
    required this.wording,
    required this.title,
    required this.details,
    required this.sections,
  });

  /// The classes that have a published result, oldest first.
  static List<(int, int)> classes(
    List<CourseworkEntry> coursework,
    List<UhpabUnit> uhpab,
  ) {
    final found = <(int, int)>{
      for (final c in coursework)
        if (c.published) (c.year, c.semester),
      for (final u in uhpab)
        if (u.published) (u.year, u.semester),
    }.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return found;
  }

  /// The average grade points of [units], or blank if there are none. Every
  /// course unit counts equally.
  static String average(Iterable<UhpabUnit> units) {
    if (units.isEmpty) return '';
    final total = units.fold<double>(0, (sum, u) => sum + u.grade.points);
    return (total / units.length).toStringAsFixed(2);
  }

  /// A transcript, or with [only] a result slip for that year and semester.
  /// Drafts are never included.
  factory ResultDocument.build({
    required StudentRecord student,
    required DocumentTemplate template,
    required List<CourseworkEntry> coursework,
    required List<UhpabUnit> uhpab,
    required String issued,
    (int, int)? only,
  }) {
    final sections = <ResultSection>[];
    final counted = <UhpabUnit>[];
    for (final (year, semester) in classes(coursework, uhpab)) {
      if (only != null && only != (year, semester)) continue;
      bool here(int y, int s) => y == year && s == semester;
      final marks = {
        for (final c in coursework)
          if (c.published && here(c.year, c.semester)) c.subjectId: c,
      };
      final board = {
        for (final u in uhpab)
          if (u.published && here(u.year, u.semester)) u.subjectId: u,
      };
      counted.addAll(board.values);
      final rows = [
        for (final id in {...marks.keys, ...board.keys})
          ResultRow(
            unit: marks[id]?.subjectName ?? board[id]!.subjectName,
            coursework: marks[id] == null
                ? ''
                : CourseworkMarks.format(marks[id]!.marks.total),
            uhpab: board[id]?.markLabel ?? '',
            grade: board[id]?.grade.letter ?? '',
            points: board[id]?.grade.points.toStringAsFixed(1) ?? '',
          ),
      ]..sort((a, b) => a.unit.compareTo(b.unit));
      final gpa = average(board.values);
      sections.add(ResultSection(
        heading: 'Year $year, Semester $semester',
        rows: rows,
        summary: gpa.isEmpty ? '' : 'GPA: $gpa',
      ));
    }
    return ResultDocument(
      wording: {...template.values},
      title: template[only == null ? 'transcriptTitle' : 'slipTitle'],
      details: [
        ResultDetail('Name', student.name),
        ResultDetail('Student number', student.nsin),
        ResultDetail(
          'Programme',
          kTrackDefinitions[student.programType]?.label ??
              student.programType.name,
        ),
        if (only == null) ...[
          ResultDetail('CGPA', average(counted)),
          ResultDetail('Award class', ''),
        ],
        ResultDetail('Date issued', issued),
      ],
      sections: sections,
    );
  }
}
