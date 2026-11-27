import 'academic_structure.dart';

/// A course unit as the school's curriculum lists it.
class CourseUnit {
  final String code;
  final String title;
  const CourseUnit(this.code, this.title);

  /// What the subject is called in the app.
  String get subjectName => '$code $title';
}

/// The standard course units, by programme, year and semester. The Registrar
/// is offered these when setting up a class, and can change them. Classes not
/// listed here are typed in by hand.
const Map<ProgramType, Map<(int, int), List<CourseUnit>>> kCourseCatalogue = {
  ProgramType.certificateNursing: {
    (1, 1): [
      CourseUnit('CN 1101', 'Foundations of Nursing I'),
      CourseUnit('CN 1102', 'Anatomy and Physiology I'),
      CourseUnit('CN 1103', 'First Aid and Emergencies'),
      CourseUnit('CN 1104', 'Microbiology'),
      CourseUnit('CN 1105', 'Personal and Communal Health'),
    ],
    (1, 2): [
      CourseUnit('CN 1201', 'Foundations of Nursing II'),
      CourseUnit('CN 1202', 'Anatomy and Physiology II'),
      CourseUnit('CN 1203', 'Sociology and Psychology'),
      CourseUnit('CN 1204', 'Introduction to Computer'),
      CourseUnit('CN 1205', 'Primary Health Care'),
    ],
  },
};

List<CourseUnit> standardUnits(ProgramType programType, int year, int semester) =>
    kCourseCatalogue[programType]?[(year, semester)] ?? const [];

/// The fixed id of a standard unit's subject, so that renaming the subject
/// does not make the app offer the unit again.
String standardSubjectId(ProgramType programType, CourseUnit unit) =>
    '${programType.name}_${unit.code.replaceAll(' ', '')}';

/// Whether [unit] is already among a class's subjects, either added from the
/// catalogue or typed in earlier by hand.
bool hasUnit(
  ProgramType programType,
  CourseUnit unit,
  Iterable<({String id, String name})> subjects,
) {
  String plain(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final id = standardSubjectId(programType, unit);
  return subjects.any(
    (s) =>
        s.id == id ||
        plain(s.name) == plain(unit.title) ||
        plain(s.name).startsWith(plain(unit.code)),
  );
}
