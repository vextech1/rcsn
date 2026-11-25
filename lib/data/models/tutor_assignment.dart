import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents one Tutor being assigned to one Subject.
///
/// Per Section 2.2 (and the correction in the planning conversation where
/// self-assign was proposed, flagged as contradicting an earlier decision,
/// and reverted): a tutor CANNOT self-assign. Every TutorAssignment
/// document is created by Admin, never by the tutor themselves. A tutor's
/// visible subject list (see Section 5, step 6) is derived entirely from
/// querying this collection for their tutorId — there is no code path
/// where a tutor writes their own assignment.
///
/// A tutor may hold multiple TutorAssignment documents — one per subject —
/// per Section 2.2's "may be assigned to multiple subjects and/or classes."
class TutorAssignment {
  final String id;
  final String tutorId;
  final String subjectId;
  final DateTime assignedAt;

  const TutorAssignment({
    required this.id,
    required this.tutorId,
    required this.subjectId,
    required this.assignedAt,
  });

  factory TutorAssignment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return TutorAssignment(
      id: doc.id,
      tutorId: data['tutorId'] as String,
      subjectId: data['subjectId'] as String,
      assignedAt: (data['assignedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tutorId': tutorId,
      'subjectId': subjectId,
      'assignedAt': Timestamp.fromDate(assignedAt),
    };
  }
}
