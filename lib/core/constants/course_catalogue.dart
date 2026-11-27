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
  // As printed on the UHPAB December 2026 examination timetable. The code
  // reads as year, semester, paper.
  ProgramType.certificateNursing: {
    (1, 1): [
      CourseUnit('CN 111', 'Anatomy and Physiology I and First Aid'),
      CourseUnit('CN 112', 'Foundations of Nursing I and Computer'),
      CourseUnit('CN 113', 'Personal and Community Health and Microbiology'),
      CourseUnit('CN 114', 'Practicals'),
    ],
    (1, 2): [
      CourseUnit('CN 121', 'Anatomy and Physiology II'),
      CourseUnit('CN 122', 'Foundations of Nursing II, Sociology and Psychology'),
      CourseUnit('CN 123', 'Primary Healthcare'),
      CourseUnit('CN 124', 'Practicals'),
    ],
    (2, 1): [
      CourseUnit('CN 211', 'Medical Nursing I and Pharmacology I'),
      CourseUnit('CN 212', 'Surgical Nursing I and Gynaecology'),
      CourseUnit('CN 213', 'Paediatric Nursing I and Palliative Care'),
      CourseUnit('CN 214', 'Practicals'),
    ],
    (2, 2): [
      CourseUnit('CN 221', 'Medical Nursing II and Pharmacology II'),
      CourseUnit('CN 222', 'Surgical Nursing II and Paediatric Nursing II'),
      CourseUnit('CN 223', 'Mental Health and Occupational Health'),
      CourseUnit('CN 224', 'Practicals'),
    ],
    (3, 1): [
      CourseUnit('CN 311', 'Tropical Medicine and Surgical Nursing III'),
      CourseUnit('CN 312', 'Reproductive Health, Guidance and Counselling'),
      CourseUnit('CN 313', 'Health Service Management and Entrepreneurship'),
      CourseUnit('CN 314', 'Practicals'),
    ],
  },

  // Certificate Midwifery: the same year-semester-paper coding, prefix CM.
  // The papers shared with Certificate Nursing carry the same titles. The
  // practical in every semester is listed by its code alone ("Practicals").
  ProgramType.certificateMidwifery: {
    (1, 1): [
      CourseUnit('CM 111', 'Anatomy and Physiology I and First Aid'),
      CourseUnit('CM 112', 'Foundations of Nursing I and Computer'),
      CourseUnit('CM 113', 'Personal and Community Health and Microbiology'),
      CourseUnit('CM 114', 'Practicals'),
    ],
    (1, 2): [
      CourseUnit('CM 121', 'Anatomy and Physiology II'),
      CourseUnit('CM 122', 'Foundations of Nursing II, Sociology and Psychology'),
      CourseUnit('CM 123', 'Primary Healthcare'),
      CourseUnit('CM 124', 'Practicals'),
    ],
    (2, 1): [
      CourseUnit('CM 211', 'Obstetric Anatomy'),
      CourseUnit('CM 212', 'Midwifery I and Pharmacology'),
      CourseUnit('CM 213', 'Paediatric Nursing I and Palliative Care'),
      CourseUnit('CM 214', 'Practicals'),
    ],
    (2, 2): [
      CourseUnit('CM 221', 'Midwifery II and Tropical Medicine'),
      CourseUnit('CM 222', 'Paediatric Nursing II and Pharmacology II'),
      CourseUnit('CM 223', 'Community Health and Occupational Health'),
      CourseUnit('CM 224', 'Practicals'),
    ],
    (3, 1): [
      CourseUnit('CM 311', 'Gynaecology and Reproductive Health'),
      CourseUnit('CM 312', 'Mental Health, Guidance and Counselling'),
      CourseUnit('CM 313', 'Health Service Management and Entrepreneurship'),
      CourseUnit('CM 314', 'Practicals'),
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
        // Every class has its own "Practicals", so that title alone says nothing.
        (unit.title != 'Practicals' && plain(s.name) == plain(unit.title)) ||
        plain(s.name).startsWith(plain(unit.code)),
  );
}
