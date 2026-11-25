import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/services/auth_service.dart';
import '../data/repositories/admin_repository.dart';
import '../data/repositories/tutor_repository.dart';
import '../data/models/admin_account.dart';
import '../data/models/tutor_account.dart';
import '../core/constants/user_role.dart';
import '../core/errors/app_failure.dart';

/// Tracks the currently signed-in Admin or Tutor and their resolved role.
///
/// Deliberately does NOT handle Student state — per Section 2.3, Student
/// access is NSIN-only with no Firebase Auth involved at all, so a signed-
/// in student concept doesn't exist here. Student "session" state (which
/// NSIN was looked up) lives in StudentProvider instead, persisted via
/// shared_preferences (see that file) — not Firebase Auth's
/// authStateChanges, which this provider is built on.
///
/// This provider resolves WHICH role a signed-in Firebase user actually
/// is (Admin vs Tutor) by checking both repositories, since Firebase Auth
/// itself has no concept of "role" — that's purely a Firestore-side fact
/// this provider derives, not something stored on the FirebaseAuth User
/// object.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final AdminRepository _adminRepository;
  final TutorRepository _tutorRepository;

  AuthProvider({
    AuthService? authService,
    AdminRepository? adminRepository,
    TutorRepository? tutorRepository,
  })  : _authService = authService ?? AuthService(),
        _adminRepository = adminRepository ?? AdminRepository(),
        _tutorRepository = tutorRepository ?? TutorRepository() {
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  User? _firebaseUser;
  UserRole? _resolvedRole;
  AdminAccount? _adminAccount;
  TutorAccount? _tutorAccount;
  bool _isResolving = false;
  AppFailure? _lastError;

  User? get firebaseUser => _firebaseUser;
  UserRole? get resolvedRole => _resolvedRole;
  AdminAccount? get adminAccount => _adminAccount;
  TutorAccount? get tutorAccount => _tutorAccount;
  bool get isSignedIn => _firebaseUser != null;
  bool get isResolving => _isResolving;
  AppFailure? get lastError => _lastError;

  /// True once a signed-in Tutor's account has resolved AND that account
  /// is active. A suspended/terminated tutor is technically "signed in"
  /// at the Firebase Auth level but should never be treated as usable —
  /// screens and route guards should check this, not just [isSignedIn].
  bool get isUsableTutorSession =>
      _resolvedRole == UserRole.tutor &&
      _tutorAccount != null &&
      _tutorAccount!.isActive;

  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    _adminAccount = null;
    _tutorAccount = null;
    _resolvedRole = null;
    _lastError = null;

    if (user == null) {
      notifyListeners();
      return;
    }

    _isResolving = true;
    notifyListeners();

    try {
      final admin = await _adminRepository.getAdmin();
      if (admin != null && admin.id == user.uid) {
        _adminAccount = admin;
        _resolvedRole = UserRole.admin;
      } else {
        final tutor = await _tutorRepository.getTutorById(user.uid);
        if (tutor != null) {
          _tutorAccount = tutor;
          _resolvedRole = UserRole.tutor;
        }
      }

      // Signed in at the Firebase Auth level, but no matching Admin or
      // Tutor document exists in Firestore. This is a real, reachable
      // state — not just a theoretical edge case — e.g. an Admin/Tutor
      // Firestore document was deleted (or the whole collection was
      // reset during setup/testing) while a device still holds a valid,
      // cached Firebase Auth session for that uid. Without this check,
      // that leaves the user "signed in" with no resolvable role: the
      // router's guard sees isSignedIn == true but resolvedRole == null
      // forever, and just silently bounces back to the login route on
      // every navigation attempt with zero explanation — exactly the
      // "I typed my credentials and nothing happened" symptom. Signing
      // out here converts that dead end into a clear, actionable error
      // message instead of a silent loop.
      if (_resolvedRole == null) {
        await _authService.signOut();
        _lastError = const UnknownFailure(
          'No account found for these credentials. If you believe this '
          'is a mistake, contact whoever manages the app\'s Firebase '
          'project.',
        );
      }
    } catch (e) {
      // Any unexpected failure during role resolution (permission
      // issue, transient network error, malformed Firestore document,
      // etc.) — previously this propagated uncaught out of an auth-
      // state-stream listener with no onError handler, which Flutter's
      // Zone swallows silently. Surfacing it as _lastError instead of
      // letting screens fail with zero feedback.
      _lastError = e is AppFailure ? e : UnknownFailure(e.toString());
    } finally {
      _isResolving = false;
      notifyListeners();
    }
  }

  /// Tutor self-registration (Section 2.2). Registration itself lives in
  /// TutorRepository — this method calls through and then lets the
  /// authStateChanges listener above pick up the resulting sign-in
  /// automatically, rather than duplicating state-setting here.
  Future<void> registerTutor({
    required String name,
    required String email,
    required String password,
  }) async {
    _lastError = null;
    try {
      await _tutorRepository.registerTutor(
        name: name,
        email: email,
        password: password,
      );
      // authStateChanges fires from the registerWithEmail call inside
      // registerTutor and resolves role automatically — no manual
      // state update needed here.
    } on AppFailure catch (e) {
      _lastError = e;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _lastError = null;
    try {
      await _authService.signInWithEmail(email: email, password: password);
    } on AppFailure catch (e) {
      _lastError = e;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    _lastError = null;
    notifyListeners();
    await _authService.signOut();
  }

  /// Clears a stale [lastError] left over from a previous, abandoned
  /// attempt.
  ///
  /// Exists specifically for the case push()-based back navigation now
  /// makes reachable: AuthProvider is a singleton that outlives any one
  /// screen, so an error set on a failed sign-in attempt (wrong
  /// password, no matching account) stays on this provider even after
  /// the user backs out of the Login screen. If they back out to
  /// RoleSelectScreen and tap Admin/Tutor again, the freshly-built Login
  /// screen would otherwise immediately show that old error before the
  /// user has typed anything on this new attempt — confusing and wrong.
  ///
  /// Callers should invoke this at the point of a USER-INITIATED fresh
  /// navigation to a Login/Setup screen (e.g. RoleSelectScreen's button
  /// handlers), not from the Login screen's own initState/build. The
  /// distinction matters: some arrivals at the Login screen are instead
  /// the ROUTER'S redirect reacting to an async failure that was set on
  /// this same provider moments earlier (see AuthProvider's own
  /// _onAuthStateChanged doc comment on the "signed in but no matching
  /// account" case) — that error is the whole reason the screen is
  /// being shown, and clearing it on the screen's own entry would erase
  /// the very message the redirect exists to surface. Clearing only at
  /// the RoleSelect tap avoids that: a redirect-driven arrival never
  /// passes through this method at all.
  void clearError() {
    _lastError = null;
    notifyListeners();
  }
}
