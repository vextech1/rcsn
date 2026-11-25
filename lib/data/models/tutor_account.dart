import 'package:cloud_firestore/cloud_firestore.dart';

/// Account status shared by Tutor and Student accounts.
///
/// Per Section 2.1: Admin can suspend or terminate either role's account.
/// Per Section 2.2: a Tutor can additionally self-terminate their own
/// account. There is no code path for a Tutor to self-suspend — only
/// Admin suspends; a tutor's own exit action is termination, not
/// suspension (suspension implies an expectation of return, which is an
/// Admin judgment call, not the tutor's own).
enum AccountStatus {
  active,
  suspended,
  terminated,
}

/// A Tutor's account record.
///
/// Per Section 2.2, a Tutor self-registers (name, email, password) — this
/// document is created by the tutor's own registration action, unlike
/// [TutorAssignment] which only Admin ever creates.
class TutorAccount {
  final String id; // matches Firebase Auth uid
  final String name;
  final String email;
  final AccountStatus status;
  final DateTime registeredAt;

  const TutorAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.registeredAt,
  });

  bool get isActive => status == AccountStatus.active;

  factory TutorAccount.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return TutorAccount(
      id: doc.id,
      name: data['name'] as String,
      email: data['email'] as String,
      status: AccountStatus.values.byName(
        data['status'] as String? ?? 'active',
      ),
      registeredAt: (data['registeredAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'status': status.name,
      'registeredAt': Timestamp.fromDate(registeredAt),
    };
  }
}
