import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';

/// Thin wrapper around Firebase Auth.
///
/// Used by Admin (first-run setup + login) and Tutor (self-register +
/// login) — per Section 2.4's permission table, both use email + password.
///
/// Deliberately has NO student-facing methods. Per Section 2.3, Student
/// access is NSIN-only with no password — that's a Firestore lookup
/// against StudentRecord, not a Firebase Auth operation at all. Adding a
/// "student sign in" method here would misrepresent what's actually
/// happening; that logic belongs in a StudentRepository querying
/// Firestore directly, not in this service.
class AuthService {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    }
  }

  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    }
  }

  Future<void> signOut() => _auth.signOut();

  AppFailure _mapFirebaseAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
        return const InvalidCredentialsFailure();
      default:
        return AuthFailure(e.message ?? 'Authentication failed.');
    }
  }
}
