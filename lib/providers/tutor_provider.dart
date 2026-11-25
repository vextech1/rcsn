import 'package:flutter/foundation.dart';
import '../data/repositories/tutor_repository.dart';
import '../data/models/tutor_account.dart';
import '../data/models/tutor_assignment.dart';
import '../data/models/subject.dart';
import '../core/errors/app_failure.dart';

/// Serves two different callers against the same underlying data —
/// deliberately not split into two providers, since both need the same
/// TutorRepository and a split would just mean keeping two providers in
/// sync with each other. The method names below are prefixed by intent
/// rather than left ambiguous:
///
/// - Methods a TUTOR calls about themselves: [watchOwnAssignments],
///   [getOwnAssignedSubjects], [selfTerminate].
/// - Methods only ADMIN calls, per Section 2.2's explicit rule that
///   tutors cannot self-assign: [assignTutorToSubject],
///   [removeAssignment], [updateTutorStatus], [watchAllTutors].
///
/// This provider does not itself enforce which screens call which
/// methods — same convention-based caveat as TutorRepository. A tutor-
/// facing screen simply never imports or calls the Admin-only methods;
/// the real boundary is still Firestore Security Rules (not yet written).
class TutorProvider extends ChangeNotifier {
  final TutorRepository _repository;

  TutorProvider({TutorRepository? repository})
      : _repository = repository ?? TutorRepository();

  AppFailure? _lastError;
  bool _isProcessing = false;

  AppFailure? get lastError => _lastError;
  bool get isProcessing => _isProcessing;

  // -----------------------------------------------------------------
  // Tutor-facing: about the currently signed-in tutor
  // -----------------------------------------------------------------

  /// Live stream of the given tutor's own assignments. An empty list
  /// here IS the "Not yet assigned, contact Admin" state from Section 5
  /// step 5 — the dashboard screen should treat empty-list, not a
  /// separate flag, as the trigger for that empty state.
  Stream<List<TutorAssignment>> watchOwnAssignments(String tutorId) {
    return _repository.watchAssignmentsForTutor(tutorId);
  }

  Future<List<Subject>> getOwnAssignedSubjects(String tutorId) {
    return _repository.getAssignedSubjects(tutorId);
  }

  /// Section 2.2's self-termination action — the one status change a
  /// tutor can make about their own account.
  Future<void> selfTerminate(String tutorId) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();
    try {
      await _repository.selfTerminate(tutorId);
    } on AppFailure catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------
  // Admin-facing: managing tutors and assignments
  // -----------------------------------------------------------------

  Stream<List<TutorAccount>> watchAllTutors() => _repository.watchAllTutors();

  /// ADMIN-ONLY per Section 2.2. Deliberately takes an explicit
  /// [tutorId] parameter rather than reading "current user" internally —
  /// this method is only ever meant to be called from an Admin screen
  /// acting on SOME OTHER tutor's id, never the caller's own, and taking
  /// an explicit parameter keeps that obvious at the call site rather
  /// than implicit.
  Future<void> assignTutorToSubject({
    required String tutorId,
    required String subjectId,
  }) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();
    try {
      await _repository.assignTutorToSubject(
        tutorId: tutorId,
        subjectId: subjectId,
      );
    } on AppFailure catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> removeAssignment(String assignmentId) async {
    _isProcessing = true;
    notifyListeners();
    try {
      await _repository.removeAssignment(assignmentId);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// ADMIN-ONLY per Section 2.1. Suspend or terminate a tutor's account —
  /// distinct from [selfTerminate] above, which only a tutor calls about
  /// themselves.
  Future<void> updateTutorStatus({
    required String tutorId,
    required AccountStatus status,
  }) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();
    try {
      await _repository.updateTutorStatus(tutorId: tutorId, status: status);
    } on AppFailure catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
