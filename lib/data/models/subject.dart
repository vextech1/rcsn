import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/academic_structure.dart';

/// A Subject is the actual unit of academic structure stored in Firestore.
///
/// Design note, worth being explicit about: Program, Year, and Semester
/// are NOT separate Firestore collections. [ProgramType] and
/// [TrackDefinition] (core/constants/academic_structure.dart) already fully
/// determine which tracks, years, and semesters exist — storing them again
/// as independent documents would create a second source of truth that
/// could drift from the constants file, which is exactly the failure mode
/// that file was built to prevent (see its doc comments on the per-year
/// semester count).
///
/// So Admin doesn't "create a Year" or "create a Semester" — those are
/// picked from [kTrackDefinitions] via dropdowns. What Admin actually
/// creates, per Section 3.3 (structure dependency) and Section 5 step 2 of
/// the project document, is a Subject: a named subject scoped to one
/// specific track/year/semester combination. Tutors get assigned to
/// specific Subjects (Section 2.2), and ContentItems (content_item.dart)
/// are uploaded into a specific Subject.
class Subject {
  final String id;
  final String name;
  final ProgramType programType;
  final int year;
  final int semester;
  final DateTime createdAt;

  const Subject({
    required this.id,
    required this.name,
    required this.programType,
    required this.year,
    required this.semester,
    required this.createdAt,
  });

  /// Validates that (year, semester) is actually a legal combination for
  /// this subject's track — e.g. rejects semester 2 of Certificate Year 3,
  /// which per Section 3.1 only has one semester. Call this before writing
  /// a new Subject, not after — catching it here means the Admin structure
  /// screen can show a real validation error instead of silently creating
  /// a phantom subject nobody can ever see content in.
  bool get hasValidYearSemester {
    final track = kTrackDefinitions[programType];
    if (track == null) return false;
    final maxSemester = track.semestersPerYear[year];
    if (maxSemester == null) return false; // year doesn't exist on this track
    return semester >= 1 && semester <= maxSemester;
  }

  /// The track this subject belongs to — convenience accessor so screens
  /// don't need to do the map lookup themselves.
  TrackDefinition get track => kTrackDefinitions[programType]!;

  factory Subject.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Subject(
      id: doc.id,
      name: data['name'] as String,
      programType: ProgramType.values.byName(data['programType'] as String),
      year: data['year'] as int,
      semester: data['semester'] as int,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'programType': programType.name,
      'year': year,
      'semester': semester,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
