import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/subject.dart';
import '../../core/constants/academic_structure.dart';
import '../../core/errors/app_failure.dart';

/// Owns all reads/writes to the Subject collection.
///
/// Per Section 2.1/2.4: only Admin builds academic structure. This
/// repository doesn't itself check "is the caller Admin" — that's an
/// auth-layer/route-guard concern (core/router, built later) — but it DOES
/// enforce the structural correctness of what's being created, which is a
/// data-integrity rule, not a permission rule: even Admin should not be
/// able to create a Subject with an invalid year/semester combination
/// (e.g. semester 2 of Certificate Year 3, which per Section 3.1 doesn't
/// exist). That check happens here, before the write, not left to the UI
/// to remember to call.
class StructureRepository {
  final FirebaseFirestore _firestore;

  StructureRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _subjects =>
      _firestore.collection('subjects');

  /// Creates a new Subject. Throws before ever touching Firestore if the
  /// year/semester combination is invalid for the given track — see
  /// [Subject.hasValidYearSemester], which is the single place this rule
  /// is defined (reusing it here rather than re-deriving the check keeps
  /// this repository from silently drifting out of sync with the model).
  Future<Subject> createSubject({
    required String name,
    required ProgramType programType,
    required int year,
    required int semester,
  }) async {
    final draft = Subject(
      id: '', // assigned by Firestore on write
      name: name,
      programType: programType,
      year: year,
      semester: semester,
      createdAt: DateTime.now(),
    );

    if (!draft.hasValidYearSemester) {
      final track = kTrackDefinitions[programType];
      final validSemesters = track?.semestersPerYear[year];
      throw UnknownFailure(
        'Year $year, Semester $semester is not valid for '
        '${track?.label ?? programType.name}. '
        '${validSemesters != null ? "That track's Year $year has $validSemesters semester(s)." : "That track has no Year $year."}',
      );
    }

    final docRef = await _subjects.add(draft.toFirestore());
    final snapshot = await docRef.get();
    return Subject.fromFirestore(snapshot);
  }

  /// Live stream of every Subject for a given track — used by the Admin
  /// structure screen to show what's already been created, and by the
  /// tutor-assignment screen's subject picker.
  Stream<List<Subject>> watchSubjectsForTrack(ProgramType programType) {
    return _subjects
        .where('programType', isEqualTo: programType.name)
        .orderBy('year')
        .orderBy('semester')
        .snapshots()
        .map((snap) => snap.docs.map(Subject.fromFirestore).toList());
  }

  /// Live stream of ALL subjects across every track — used sparingly
  /// (e.g. Admin's full structure overview); most screens want
  /// [watchSubjectsForTrack] or a more scoped query instead.
  Stream<List<Subject>> watchAllSubjects() {
    return _subjects.snapshots().map(
          (snap) => snap.docs.map(Subject.fromFirestore).toList(),
        );
  }

  Future<Subject?> getSubjectById(String subjectId) async {
    final doc = await _subjects.doc(subjectId).get();
    if (!doc.exists) return null;
    return Subject.fromFirestore(doc);
  }

  Future<void> deleteSubject(String subjectId) async {
    // Note: this does NOT cascade-delete ContentItems or TutorAssignments
    // referencing this subject. That cleanup is deliberately left as a
    // Cloud Function concern (same reasoning as NotificationService's
    // send-side — cascade deletes across collections are safer done
    // server-side with a transaction than trusted to a client call that
    // might get interrupted halfway through). Flagging this now so it
    // isn't silently assumed to be handled.
    await _subjects.doc(subjectId).delete();
  }
}
