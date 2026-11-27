import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/user_role.dart';

enum StaffStatus { active, suspended }

/// A Principal, Deputy Principal, Registrar, Bursar or other staff account.
///
/// Document ID = Firebase Auth uid. The Principal's app creates Registrar
/// and Bursar records and flips their status; the first Principal record is
/// created out-of-band (tools/bootstrap-principal.js). What each caller may
/// write is enforced by the `staff` rules in firestore.rules.
class StaffAccount {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final StaffStatus status;
  final DateTime? createdAt;
  final String? createdBy;

  /// The custom position title ("Askari", "Accountant", ...). Only set for
  /// [UserRole.staffMember]; the other roles are their own position.
  final String? position;

  const StaffAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.createdAt,
    this.createdBy,
    this.position,
  });

  bool get isActive => status == StaffStatus.active;

  /// What to call this person's position in the UI.
  String get positionLabel {
    final custom = position?.trim();
    if (role == UserRole.staffMember && custom != null && custom.isNotEmpty) {
      return custom;
    }
    return role.label;
  }

  factory StaffAccount.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;

    final roleName = data['role'] as String;
    final role = UserRole.values.firstWhere(
      (r) => r.name == roleName && r.isStaff,
      orElse: () => throw FormatException('Unknown staff role "$roleName"'),
    );

    // Fail closed: anything that is not exactly "active" is treated as
    // suspended.
    final status = data['status'] == 'active'
        ? StaffStatus.active
        : StaffStatus.suspended;

    return StaffAccount(
      id: doc.id,
      name: data['name'] as String,
      email: data['email'] as String,
      role: role,
      status: status,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] as String?,
      position: data['position'] as String?,
    );
  }
}
