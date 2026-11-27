import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/user_role.dart';
import 'staff_account.dart';

/// One entry in the list shown on the Staff screen before sign-in.
///
/// Four positions are built in (Principal, Deputy Principal, Registrar,
/// Bursar). Anything else (Askari, Accountant, Clinical Instructor, ...) is
/// a custom position the Principal or Deputy Principal added; those live in
/// the `staff_positions` collection and all sign in as
/// [UserRole.staffMember].
///
/// Picking a position does not grant anything. Accounts are still created by
/// the Principal or Deputy Principal; the list only tells the app which
/// position the person is signing in as, so a wrong pick is caught.
class StaffPosition {
  /// Firestore document id for a custom position, the role name for a
  /// built-in one.
  final String id;
  final String title;

  /// The role an account in this position has.
  final UserRole role;
  final bool isCustom;

  const StaffPosition({
    required this.id,
    required this.title,
    required this.role,
    this.isCustom = false,
  });

  static const StaffPosition principal = StaffPosition(
    id: 'principal',
    title: 'Principal',
    role: UserRole.principal,
  );

  static const StaffPosition deputyPrincipal = StaffPosition(
    id: 'deputyPrincipal',
    title: 'Deputy Principal',
    role: UserRole.deputyPrincipal,
  );

  static const StaffPosition registrar = StaffPosition(
    id: 'registrar',
    title: 'Registrar',
    role: UserRole.registrar,
  );

  static const StaffPosition bursar = StaffPosition(
    id: 'bursar',
    title: 'Bursar',
    role: UserRole.bursar,
  );

  /// The built-in positions, in the order they are listed.
  static const List<StaffPosition> defaults = [
    principal,
    deputyPrincipal,
    registrar,
    bursar,
  ];

  /// Principal and Deputy Principal have exactly one holder. They stay on the
  /// list (people need to find them to sign in); the sign-in itself only
  /// works for the account that really holds the position.
  bool get isSingleHolder =>
      role == UserRole.principal || role == UserRole.deputyPrincipal;

  /// True if [account] is someone in this position.
  bool matches(StaffAccount account) {
    if (isCustom) {
      return account.role == UserRole.staffMember &&
          (account.position ?? '').trim().toLowerCase() ==
              title.trim().toLowerCase();
    }
    return account.role == role;
  }

  factory StaffPosition.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return StaffPosition(
      id: doc.id,
      title: data['title'] as String,
      role: UserRole.staffMember,
      isCustom: true,
    );
  }
}
