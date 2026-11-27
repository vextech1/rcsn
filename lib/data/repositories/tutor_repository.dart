import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tutor_account.dart';
import '../models/tutor_assignment.dart';
import '../models/subject.dart';
import '../services/auth_service.dart';

/// Owns Tutor accounts and Tutor→Subject assignments.
///
/// The critical rule enforced by this repository's shape, not just its
/// comments: [registerTutor] and [assignTutorToSubject] are separate
/// methods with no path connecting them. A tutor calling [registerTutor]
/// has no way, through this repository, to also create a
/// [TutorAssignment] for themselves — that method takes no caller-identity
/// shortcut, it simply doesn't exist here. Per Section 2.2 (and the
/// planning-conversation correction where self-assign was proposed,
/// caught as contradicting an earlier decision, and reverted):
/// [assignTutorToSubject] is called ONLY from Admin-facing screens. This
/// repository doesn't runtime-check "is the caller Admin" — the real
/// enforcement is that the tutor-facing UI (screens/tutor/) never calls
/// this method at all, and the admin-facing UI (screens/admin/tutors/) is
/// the only caller. Firestore security rules (not yet written — flagged
/// as a real gap below) are what make this actually secure rather than
/// merely convention.
class TutorRepository {
  final FirebaseFirestore _firestore;
  final AuthService _authService;

  TutorRepository({
    FirebaseFirestore? firestore,
    AuthService? authService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _authService = authService ?? AuthService();

  CollectionReference<Map<String, dynamic>> get _tutors =>
      _firestore.collection('tutors');

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _firestore.collection('tutor_assignments');

  /// Tutor self-registration (Section 2.2). Creates both the Firebase Auth
  /// user and the corresponding TutorAccount document. Does NOT create any
  /// TutorAssignment — a freshly registered tutor has zero subject access
  /// by construction, matching Section 5 step 5's "sees a 'Not yet
  /// assigned' state."
  Future<TutorAccount> registerTutor({
    required String name,
    required String email,
    required String password,
  }) async {
    final user = await _authService.registerWithEmail(
      email: email,
      password: password,
    );

    final account = TutorAccount(
      id: user.uid,
      name: name,
      email: email,
      status: AccountStatus.active,
      registeredAt: DateTime.now(),
    );

    await _tutors.doc(user.uid).set(account.toFirestore());
    return account;
  }

  Future<TutorAccount?> getTutorById(String tutorId) async {
    final doc = await _tutors.doc(tutorId).get();
    if (!doc.exists) return null;
    return TutorAccount.fromFirestore(doc);
  }

  Stream<List<TutorAccount>> watchAllTutors() {
    return _tutors.snapshots().map(
          (snap) => snap.docs.map(TutorAccount.fromFirestore).toList(),
        );
  }

  /// ADMIN-ONLY in intent, per the class doc above. Creates a
  /// TutorAssignment linking [tutorId] to [subjectId]. There is no
  /// "assignSelf" variant of this method — that absence is deliberate.
  ///
  /// Uses a composite document ID of the form `{tutorId}_{subjectId}`
  /// (e.g. "abc123_xyz789"). This is a deliberate data-model choice, not
  /// a convenience: Firestore Security Rules cannot perform collection-
  /// group queries or `where` clauses inside `get()`/`exists()` calls.
  /// A composite ID lets isAssignedToSubject() in firestore.rules check
  /// assignment with a single `exists()` call, which IS supported.
  Future<TutorAssignment> assignTutorToSubject({
    required String tutorId,
    required String subjectId,
  }) async {
    final assignmentId = '${tutorId}_$subjectId';
    final assignment = TutorAssignment(
      id: assignmentId,
      tutorId: tutorId,
      subjectId: subjectId,
      assignedAt: DateTime.now(),
    );
    await _assignments.doc(assignmentId).set(assignment.toFirestore());
    final snapshot = await _assignments.doc(assignmentId).get();
    return TutorAssignment.fromFirestore(snapshot);
  }

  /// Who teaches a subject.
  Future<List<String>> tutorIdsFor(String subjectId) async {
    final found =
        await _assignments.where('subjectId', isEqualTo: subjectId).get();
    return [for (final doc in found.docs) doc.data()['tutorId'] as String];
  }

  /// ADMIN-ONLY. Removes a tutor's access to a specific subject without
  /// touching their account status — distinct from suspension/termination
  /// (Section 2.1), which is account-wide, not subject-specific.
  Future<void> removeAssignment(String assignmentId) async {
    await _assignments.doc(assignmentId).delete();
  }

  /// Live stream of a tutor's own assignments — this is what powers both
  /// the tutor dashboard's subject list AND the "Not yet assigned, contact
  /// Admin" empty state (Section 5 step 5): an empty list from this stream
  /// IS that empty state, not a separate flag to check.
  Stream<List<TutorAssignment>> watchAssignmentsForTutor(String tutorId) {
    return _assignments
        .where('tutorId', isEqualTo: tutorId)
        .snapshots()
        .map((snap) => snap.docs.map(TutorAssignment.fromFirestore).toList());
  }

  /// Resolves a tutor's assignments into the actual Subject documents,
  /// since screens generally want to show subject names, not raw
  /// assignment records. Kept as a separate method rather than folded
  /// into [watchAssignmentsForTutor] because it requires N additional
  /// reads (one per assignment) — callers that only need to check
  /// "is this list empty" for the empty-state check should prefer the
  /// cheaper stream above.
  Future<List<Subject>> getAssignedSubjects(String tutorId) async {
    final assignmentSnap =
        await _assignments.where('tutorId', isEqualTo: tutorId).get();

    if (assignmentSnap.docs.isEmpty) return [];

    final subjectIds = assignmentSnap.docs
        .map((doc) => TutorAssignment.fromFirestore(doc).subjectId)
        .toList();

    final subjects = <Subject>[];
    for (final id in subjectIds) {
      final doc = await _firestore.collection('subjects').doc(id).get();
      if (doc.exists) subjects.add(Subject.fromFirestore(doc));
    }
    return subjects;
  }

  /// ADMIN-ONLY (Section 2.1). Suspend or terminate a tutor's account.
  Future<void> updateTutorStatus({
    required String tutorId,
    required AccountStatus status,
  }) async {
    await _tutors.doc(tutorId).update({'status': status.name});
  }

  /// Self-service termination (Section 2.2) — the one account-status
  /// change a tutor CAN make about their own account, distinct from
  /// suspension, which per Section 2.1 is Admin-only. In practice, a
  /// tutor-facing screen would call this with the currently signed-in
  /// tutor's own id; nothing here prevents calling it with a different
  /// id, which is the same convention-not-runtime-enforcement caveat as
  /// [assignTutorToSubject] — real enforcement needs Firestore security
  /// rules, not just which screens choose to call which methods.
  Future<void> selfTerminate(String tutorId) async {
    await _tutors.doc(tutorId).update({
      'status': AccountStatus.terminated.name,
    });
  }
}
