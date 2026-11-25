import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student_record.dart';
import '../models/tutor_account.dart' show AccountStatus;
import '../../core/constants/academic_structure.dart';
import '../../core/utils/nsin_validator.dart';
import '../../core/errors/app_failure.dart';

/// Owns StudentRecord creation (Admin, at admission) and NSIN lookup
/// (Student, at app entry).
///
/// Deliberate separation of concerns, worth stating explicitly: this
/// repository checks whether an NSIN EXISTS in Firestore.
/// [NsinValidator] (core/utils/nsin_validator.dart) checks whether an
/// NSIN is well-FORMED. These are different questions — a syntactically
/// perfect NSIN can still not exist (typo, or a genuinely fake number),
/// and format validation should reject obvious garbage before ever
/// spending a network round-trip on a lookup that was always going to
/// fail. [findByNsin] assumes the input has already passed
/// [NsinValidator.isValidFormat] — callers (the student search screen)
/// are expected to check format first and show a format error locally
/// before ever calling this method.
class StudentRepository {
  final FirebaseFirestore _firestore;

  StudentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  /// ADMIN-ONLY in intent (Section 2.3 — students do not self-register;
  /// this is the admission-time entry action from Section 5 step 4).
  /// Same convention-not-runtime-enforcement caveat as the Admin-only
  /// methods in TutorRepository and ContentRepository — Firestore
  /// security rules are the real boundary, not yet written.
  ///
  /// [nsin] is stored exactly as given — see StudentRecord's doc comment
  /// on why it's kept as a raw string rather than parsed into segments
  /// while the real format is still being confirmed against the school's
  /// records.
  Future<StudentRecord> createStudentRecord({
    required String nsin,
    required String name,
    required ProgramType programType,
    required int year,
    required int semester,
  }) async {
    final normalized = NsinValidator.normalize(nsin);

    // Guard against Admin accidentally creating two records for the same
    // NSIN — a real, easy-to-make data-entry mistake at admission time
    // when entering many students in one sitting.
    final existing = await findByNsin(normalized);
    if (existing != null) {
      throw UnknownFailure(
        'A student record already exists for NSIN $normalized.',
      );
    }

    final record = StudentRecord(
      id: '',
      nsin: normalized,
      name: name,
      programType: programType,
      year: year,
      semester: semester,
      status: AccountStatus.active,
      admittedAt: DateTime.now(),
    );

    final docRef = await _students.add(record.toFirestore());
    final snapshot = await docRef.get();
    return StudentRecord.fromFirestore(snapshot);
  }

  /// The actual Section 2.3 entry point: exact-match NSIN lookup. Returns
  /// null if no record matches — the search screen should map that null
  /// to [NsinNotFoundFailure] rather than this method throwing it
  /// directly, since "not found" is an expected, common outcome here
  /// (a mistyped NSIN), not an exceptional one.
  Future<StudentRecord?> findByNsin(String nsin) async {
    final normalized = NsinValidator.normalize(nsin);
    final query =
        await _students.where('nsin', isEqualTo: normalized).limit(1).get();

    if (query.docs.isEmpty) return null;
    return StudentRecord.fromFirestore(query.docs.first);
  }

  /// ADMIN-ONLY (Section 2.1). Suspend, terminate, or otherwise update a
  /// student's status (e.g. "terminated course").
  Future<void> updateStudentStatus({
    required String studentId,
    required AccountStatus status,
  }) async {
    await _students.doc(studentId).update({'status': status.name});
  }

  Stream<List<StudentRecord>> watchAllStudents() {
    return _students.snapshots().map(
          (snap) => snap.docs.map(StudentRecord.fromFirestore).toList(),
        );
  }
}
