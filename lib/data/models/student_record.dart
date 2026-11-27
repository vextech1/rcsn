import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/academic_structure.dart';
import 'tutor_account.dart' show AccountStatus;

/// A Student's admission record.
///
/// Per Section 2.3: students do NOT self-register. This document is
/// created by Admin at admission time (Section 5, step 4), before the
/// student ever opens the app. The student's only interaction is later
/// searching for this record by [nsin] — there is no student-writable
/// field on this model at all.
///
/// SCOPE BOUNDARY — ACADEMIC DATA ONLY, NEVER BURSAR/FEES: per explicit
/// product decision, an NSIN lookup returns ALL of a student's academic
/// information, but exclusively that — never fees/Bursar data. This
/// model must NEVER gain a fees-related field, and the `students`
/// Firestore collection this model reads from must NEVER be the storage
/// location for fees data, even as "just one more field on the same
/// document." The reason this matters structurally, not just as a
/// comment: Section 2.3's entire security model — NSIN-only, no
/// password — was explicitly accepted ONLY because the data behind it is
/// non-sensitive (classwork, timetables). A future Bursar feature
/// (flagged as future scope in Section 8 of the project document,
/// explicitly requiring its own password protection) MUST store fees
/// data in a completely separate Firestore collection with its own
/// repository and its own access gate — never appended here. If a fees
/// field ever appears in this class or in a `students` document, the
/// NSIN-only access model has silently become unsafe for every existing
/// caller of this model, including the plain academic dashboard.
///
/// Design note on [nsin]: stored as the raw string exactly as issued
/// (e.g. "JAN21/U028/CCN/002"), NOT pre-parsed into separate intake/
/// course/sequence fields. This is deliberate, not an oversight: the
/// course-code segment is still unconfirmed for five of the six tracks
/// (see StudentNumber's doc comments) — the person providing this format
/// info explicitly said "we will validate everything once exact
/// information is confirmed." Splitting the NSIN into structured fields
/// now would mean guessing at a parsing rule that might not hold for
/// every track. The raw string is enough for exact-match lookup (which is
/// all Section 2.3 requires); parsed fields can be added later as a
/// migration once the real format is confirmed, without touching this
/// model's core shape.
class StudentRecord {
  final String id;
  final String nsin;
  final String name;
  final ProgramType programType;
  final int year;
  final int semester;
  final AccountStatus status;
  final DateTime admittedAt;

  const StudentRecord({
    required this.id,
    required this.nsin,
    required this.name,
    required this.programType,
    required this.year,
    required this.semester,
    required this.status,
    required this.admittedAt,
  });

  bool get isActive => status == AccountStatus.active;

  /// The only fields this model will ever read from a `students`
  /// document — see the class doc above on why fees/Bursar data must
  /// never appear here.
  static const _knownFields = {
    'nsin',
    'name',
    'programType',
    'year',
    'semester',
    'status',
    'admittedAt',
  };

  factory StudentRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;

    // Defensive check, not just documentation: if a field shows up on a
    // `students` document that this model doesn't know about, fail loudly
    // here rather than silently ignoring it. A field named something like
    // "feesBalance" or "bursarNotes" appearing here would mean the
    // students/Bursar boundary described in this class's doc comment has
    // already been violated at the database level — better to surface
    // that immediately (as a crash during development/testing) than have
    // it quietly work while some other, less careful code path reads the
    // raw document and exposes it.
    final unexpected = data.keys.toSet().difference(_knownFields);
    assert(
      unexpected.isEmpty,
      'StudentRecord.fromFirestore found unexpected field(s) on a '
      'students document: $unexpected. This model must only ever contain '
      'academic data — if this is Bursar/fees data, it belongs in a '
      'separate collection, not here. See this class\'s doc comment.',
    );

    return StudentRecord(
      id: doc.id,
      nsin: data['nsin'] as String,
      name: data['name'] as String,
      programType: ProgramType.values.byName(data['programType'] as String),
      year: data['year'] as int,
      semester: data['semester'] as int,
      status: AccountStatus.values.byName(
        data['status'] as String? ?? 'active',
      ),
      admittedAt: (data['admittedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nsin': nsin,
      'name': name,
      'programType': programType.name,
      'year': year,
      'semester': semester,
      'status': status.name,
      'admittedAt': Timestamp.fromDate(admittedAt),
    };
  }
}
