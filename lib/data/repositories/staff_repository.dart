import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/constants/user_role.dart';
import '../../core/errors/app_failure.dart';
import '../models/staff_account.dart';

/// Reads and manages staff records. Runs entirely on the free Spark plan:
/// no Cloud Functions, so the Firestore rules for `staff` are the security
/// boundary (only the Principal can create a Registrar/Bursar or flip
/// someone's status; nobody can delete staff).
///
/// Creating an account uses a SECOND Firebase app instance for the Auth
/// call. Calling createUserWithEmailAndPassword on the default instance
/// would sign the Principal out and sign in as the new user. The Firestore
/// write still goes through the default instance, i.e. the Principal's own
/// session, which is what the rules check.
class StaffRepository {
  static const _secondaryAppName = 'staff-creator';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StaffRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
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

  /// Creates a Registrar or Bursar, then emails them a link to set their
  /// own password. The account is created with a random password that
  /// nobody (including the Principal) ever sees.
  Future<void> createStaff({
    required String name,
    required String email,
    required UserRole role,
  }) async {
    if (role != UserRole.registrar && role != UserRole.bursar) {
      throw const StaffManagementFailure(
        'Only a Registrar or Bursar can be added. There is one Principal.',
      );
    }
    final principalUid = _auth.currentUser?.uid;
    if (principalUid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }

    final secondary = FirebaseAuth.instanceFor(app: await _secondaryApp());
    try {
      final UserCredential credential;
      try {
        credential = await secondary.createUserWithEmailAndPassword(
          email: email,
          password: _randomPassword(),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw const StaffManagementFailure(
            'An account with that email already exists.',
          );
        }
        if (e.code == 'invalid-email') {
          throw const StaffManagementFailure('Enter a valid email address.');
        }
        throw StaffManagementFailure(
          e.message ?? 'Could not create the account.',
        );
      }

      final newUser = credential.user!;
      try {
        await _staff.doc(newUser.uid).set({
          'name': name,
          'email': email,
          'role': role.name,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': principalUid,
        });
      } catch (e) {
        // Do not leave a login with no staff record behind.
        await newUser.delete().catchError((_) {});
        throw _mapWriteError(e);
      }

      try {
        await secondary.sendPasswordResetEmail(email: email);
      } on FirebaseAuthException catch (e) {
        throw StaffManagementFailure(
          'The account was created, but the invite email could not be sent '
          '(${e.message ?? e.code}). Use "Resend invite" on the staff list.',
        );
      }
    } finally {
      await secondary.signOut();
    }
  }

  /// Sends (or re-sends) the set-your-password email to a staff member.
  Future<void> resendInvite(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw StaffManagementFailure(
        'The invite email could not be sent (${e.message ?? e.code}).',
      );
    }
  }

  /// Suspend or reactivate someone else. Enforced by the Firestore rules:
  /// Principal only, never themselves, never the Principal record.
  Future<void> setStatus({
    required String staffId,
    required StaffStatus status,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      await _staff.doc(staffId).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    } catch (e) {
      throw _mapWriteError(e);
    }
  }

  Future<FirebaseApp> _secondaryApp() async {
    for (final app in Firebase.apps) {
      if (app.name == _secondaryAppName) return app;
    }
    return Firebase.initializeApp(
      name: _secondaryAppName,
      options: Firebase.app().options,
    );
  }

  String _randomPassword() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  AppFailure _mapWriteError(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return const UnauthorizedActionFailure(
        'Only the Principal can manage staff.',
      );
    }
    if (e is AppFailure) return e;
    return const StaffManagementFailure(
      'Could not complete that action. Please try again.',
    );
  }
}
