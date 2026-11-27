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
/// boundary. The Principal and Deputy Principal can create Registrars,
/// Bursars and other staff and flip their status; only the Principal can
/// create or terminate the Deputy Principal; nobody can delete staff.
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

  /// All staff, newest first. Only the Principal and Deputy Principal are
  /// allowed to list.
  Stream<List<StaffAccount>> watchAllStaff() {
    return _staff.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(StaffAccount.fromFirestore).toList(),
        );
  }

  /// Creates a staff account, then emails them a link to set their own
  /// password. The account is created with a random password that nobody
  /// (including whoever created it) ever sees.
  ///
  /// [role] is Registrar, Bursar, Deputy Principal (Principal only) or
  /// [UserRole.staffMember]; for the last one [position] is the title from
  /// the positions list ("Askari", "Accountant", ...).
  Future<void> createStaff({
    required String name,
    required String email,
    required UserRole role,
    String? position,
  }) async {
    const creatable = [
      UserRole.registrar,
      UserRole.bursar,
      UserRole.deputyPrincipal,
      UserRole.staffMember,
    ];
    if (!creatable.contains(role)) {
      throw const StaffManagementFailure(
        'That position cannot be added here. There is one Principal.',
      );
    }
    final positionTitle = position?.trim();
    if (role == UserRole.staffMember &&
        (positionTitle == null || positionTitle.length < 2)) {
      throw const StaffManagementFailure('Choose a position.');
    }
    final creatorUid = _auth.currentUser?.uid;
    if (creatorUid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }

    // One Deputy Principal at a time. Checked here, before any login is
    // created (the rules cannot count records).
    if (role == UserRole.deputyPrincipal) {
      try {
        final existing = await _staff
            .where('role', isEqualTo: UserRole.deputyPrincipal.name)
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          throw const StaffManagementFailure(
            'There is already a Deputy Principal. Terminate them first to '
            'appoint a new one.',
          );
        }
      } catch (e) {
        throw _mapWriteError(e);
      }
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
          if (role == UserRole.staffMember) 'position': positionTitle,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': creatorUid,
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
  /// Principal or Deputy Principal, never themselves, never the Principal
  /// record. The Deputy Principal's record can only be terminated (suspended,
  /// one-way) and only by the Principal.
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
        'Only the Principal or Deputy Principal can do that.',
      );
    }
    if (e is AppFailure) return e;
    return const StaffManagementFailure(
      'Could not complete that action. Please try again.',
    );
  }
}
