import '../../data/repositories/tutor_repository.dart';

/// Answers one question: is a given tutor authorized to act on a given
/// subject?
///
/// Extracted deliberately out of ContentRepository, where this check
/// originally lived directly against an injected TutorRepository. That
/// created a repository-to-repository dependency (ContentRepository
/// importing and instantiating TutorRepository internally) which risked
/// becoming a precedent — if Content can reach into Tutor, nothing
/// structurally stops Student from later reaching into Content, and
/// repositories start forming a tangled dependency graph instead of each
/// owning one collection cleanly.
///
/// This class still depends on TutorRepository (it has to — assignment
/// data lives there), but the dependency direction is now: this checker
/// depends on TutorRepository, and ContentRepository depends on THIS
/// checker, not on TutorRepository directly. That keeps ContentRepository
/// scoped to content concerns only, and makes the authorization check
/// independently reusable — e.g. a future "can this tutor archive this
/// item" check, or a StudentRepository visibility check, can depend on
/// the same checker without either repository needing to know about the
/// other.
class TutorAuthorizationChecker {
  final TutorRepository _tutorRepository;

  TutorAuthorizationChecker({TutorRepository? tutorRepository})
      : _tutorRepository = tutorRepository ?? TutorRepository();

  /// True if [tutorId] has an active TutorAssignment for [subjectId].
  /// This is the single check backing Section 2.2's "a tutor cannot
  /// upload into a subject they haven't been assigned to."
  Future<bool> isTutorAssignedToSubject({
    required String tutorId,
    required String subjectId,
  }) async {
    final assignedSubjects =
        await _tutorRepository.getAssignedSubjects(tutorId);
    return assignedSubjects.any((s) => s.id == subjectId);
  }
}
