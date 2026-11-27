import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/errors/app_failure.dart';

/// First-run setup: "does this school have a Principal yet, and if not,
/// register one".
///
/// The marker is the single document `system/setup`. It is created exactly
/// once, in the SAME atomic batch as the Principal's own `staff/{uid}`
/// record, and firestore.rules only allow that pair while the marker does
/// not exist. So there is never a Principal without a marker or a marker
/// without a Principal, and after the first registration nobody can
/// register again.
class SetupRepository {
  static const _secondaryAppName = 'principal-setup';

  final FirebaseFirestore _firestore;

  SetupRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// True once the Principal has registered. Throws when the answer cannot
  /// be determined (offline, rules not deployed); the caller must treat
  /// that as "unknown", never as "not set up".
  Future<bool> isSetupComplete() async {
    final doc = await _firestore.collection('system').doc('setup').get();
    return doc.exists;
  }

  /// Creates the Principal's login and records them as the school's
  /// Principal. Uses a secondary Firebase app so the main auth session is
  /// untouched while this runs (otherwise the auth listener would try to
  /// resolve a role before the staff record exists). The caller signs in
  /// afterwards with the same credentials.
  Future<void> registerPrincipal({
    required String name,
    required String email,
    required String password,
  }) async {
    final app = await _secondaryApp();
    final auth = FirebaseAuth.instanceFor(app: app);
    final firestore = FirebaseFirestore.instanceFor(app: app);
    final cleanEmail = email.trim().toLowerCase();

    final UserCredential credential;
    try {
      credential = await auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }

    final user = credential.user!;
    try {
      final batch = firestore.batch();
      batch.set(firestore.collection('system').doc('setup'), {
        'principalUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(firestore.collection('staff').doc(user.uid), {
        'name': name.trim(),
        'email': cleanEmail,
        'role': 'principal',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
      });
      await batch.commit();
    } catch (e) {
      // Undo the half-finished login so the person can try again with the
      // same email.
      try {
        await user.delete();
      } catch (_) {}
      await auth.signOut();
      throw _mapWriteError(e);
    }

    await auth.signOut();
  }

  AppFailure _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return const StaffManagementFailure(
          'An account with that email already exists. Use a different email.',
        );
      case 'invalid-email':
        return const StaffManagementFailure('Enter a valid email address.');
      case 'weak-password':
        return const StaffManagementFailure(
          'That password is too weak. Use at least 8 characters.',
        );
      case 'network-request-failed':
        return const StaffManagementFailure(
          'No internet connection. Check your connection and try again.',
        );
      default:
        return StaffManagementFailure(
          e.message ?? 'Could not create the account.',
        );
    }
  }

  AppFailure _mapWriteError(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return const StaffManagementFailure(
        'This school has already been set up. Ask the Principal for an '
        'account.',
      );
    }
    if (e is FirebaseException && e.code == 'unavailable') {
      return const StaffManagementFailure(
        'No internet connection. Check your connection and try again.',
      );
    }
    return StaffManagementFailure('Setup failed: $e');
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
}
