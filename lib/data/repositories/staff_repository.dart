import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/user_role.dart';
import '../../core/errors/app_failure.dart';
import '../models/staff_account.dart';

/// Reads staff records and calls the staff-management Cloud Functions.
///
/// Staff accounts cannot be created or changed from the client. Creating an
/// Auth user in-app would sign the creator out, and a client write path to
/// the `staff` collection would let any user grant themselves a role. So
/// every mutation goes through a Principal-only callable function, which
/// re-checks the caller's authority server-side.
class StaffRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  StaffRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _staff =>
      _firestore.collection('staff');

  /// The signed-in user's own staff record, or null if they are not staff.
  Future<StaffAccount?> getStaffById(String uid) async {
    final doc = await _staff.doc(uid).get();
    if (!doc.exists) return null;
    return StaffAccount.fromFirestore(doc);
  }

  /// All staff, newest first. Only the Principal is allowed to list.
  Stream<List<StaffAccount>> watchAllStaff() {
    return _staff.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(StaffAccount.fromFirestore).toList(),
        );
  }

  /// Creates a Registrar or Bursar account, then emails them a link to set
  /// their own password. The account is created with a random password that
  /// nobody knows, so the reset email is the only way in.
  Future<void> createStaff({
    required String name,
    required String email,
    required UserRole role,
  }) async {
    try {
      await _functions.httpsCallable('createStaff').call({
        'name': name,
        'email': email,
        'role': role.name,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsException(e);
    }
    await resendInvite(email);
  }

  /// Sends (or re-sends) the set-your-password email to a staff member.
  Future<void> resendInvite(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw StaffManagementFailure(
        'The account exists, but the invite email could not be sent '
        '(${e.message ?? e.code}). Use "Resend invite" on the staff list.',
      );
    }
  }

  Future<void> setStatus({
    required String staffId,
    required StaffStatus status,
  }) async {
    try {
      await _functions.httpsCallable('setStaffStatus').call({
        'staffId': staffId,
        'status': status.name,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsException(e);
    }
  }

  AppFailure _mapFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return UnauthorizedActionFailure(e.message);
      case 'unauthenticated':
        return const UnauthorizedActionFailure('Please sign in again.');
      default:
        return StaffManagementFailure(
          e.message ?? 'Could not complete that action. Please try again.',
        );
    }
  }
}
