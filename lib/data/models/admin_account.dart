import 'package:cloud_firestore/cloud_firestore.dart';

/// The single Admin account.
///
/// Per Section 2.1, there is exactly one Admin — no self-registration
/// screen exists for this role. This document is created once, by the
/// first-run setup flow, and that flow must check whether an AdminAccount
/// already exists before allowing creation of a new one (see
/// AdminSetupRepository once written) — this model itself doesn't enforce
/// singularity, the repository/setup-flow logic does.
class AdminAccount {
  final String id; // matches Firebase Auth uid
  final String name;
  final String email;
  final DateTime createdAt;

  const AdminAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  factory AdminAccount.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return AdminAccount(
      id: doc.id,
      name: data['name'] as String,
      email: data['email'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
