import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/services/auth_service.dart';
import '../data/repositories/staff_repository.dart';
import '../data/repositories/staff_position_repository.dart';
import '../data/repositories/tutor_repository.dart';
import '../data/models/staff_account.dart';
import '../data/models/staff_position.dart';
import '../data/models/tutor_account.dart';
import '../core/constants/user_role.dart';
import '../core/errors/app_failure.dart';

/// Tracks the currently signed-in staff member or Tutor and their
/// resolved role.
///
/// Deliberately does NOT handle Student state. Student "session" state
/// (which NSIN was looked up) lives in StudentProvider instead; this
/// provider is built on Firebase Auth's authStateChanges.
///
/// Firebase Auth itself has no concept of "role", so this provider
/// resolves it from Firestore: a `staff` record (Principal, Deputy
/// Principal, Registrar, Bursar or another staff position) wins, otherwise
/// a `tutors` record makes the user a Tutor.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final StaffRepository _staffRepository;
  final TutorRepository _tutorRepository;
  final StaffPositionRepository _positionRepository;

  AuthProvider({
    AuthService? authService,
    StaffRepository? staffRepository,
    TutorRepository? tutorRepository,
    StaffPositionRepository? positionRepository,
  })  : _authService = authService ?? AuthService(),
        _staffRepository = staffRepository ?? StaffRepository(),
        _tutorRepository = tutorRepository ?? TutorRepository(),
        _positionRepository = positionRepository ?? StaffPositionRepository() {
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  User? _firebaseUser;
  UserRole? _resolvedRole;
  StaffAccount? _staffAccount;
  TutorAccount? _tutorAccount;
  bool _isResolving = false;
  AppFailure? _lastError;

  // An error that must survive the sign-out it causes. When role
  // resolution rejects a session it signs the user out, which fires the
  // auth-state listener again with a null user; without this the listener
  // would wipe the very message explaining why.
  AppFailure? _errorAfterSignOut;

  // The position the person picked on the Staff screen for the sign-in in
  // progress. Consumed (and cleared) when the account resolves, so a wrong
  // pick is rejected instead of silently landing on another dashboard.
  StaffPosition? _selectedPosition;

  User? get firebaseUser => _firebaseUser;
  UserRole? get resolvedRole => _resolvedRole;
  StaffAccount? get staffAccount => _staffAccount;
  TutorAccount? get tutorAccount => _tutorAccount;
  bool get isSignedIn => _firebaseUser != null;
  bool get isResolving => _isResolving;
  AppFailure? get lastError => _lastError;

  /// True once a signed-in staff member's record has resolved AND is
  /// active. Suspended staff are rejected during resolution, so this is a
  /// belt-and-braces check for route guards.
  bool get isUsableStaffSession =>
      _resolvedRole != null &&
      _resolvedRole!.isStaff &&
      _staffAccount != null &&
      _staffAccount!.isActive;

  /// True once a signed-in Tutor's account has resolved AND that account
  /// is active. A suspended/terminated tutor is technically "signed in"
  /// at the Firebase Auth level but should never be treated as usable.
  bool get isUsableTutorSession =>
      _resolvedRole == UserRole.tutor &&
      _tutorAccount != null &&
      _tutorAccount!.isActive;

  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    _staffAccount = null;
    _tutorAccount = null;
    _resolvedRole = null;

    if (user == null) {
      _lastError = _errorAfterSignOut;
      _errorAfterSignOut = null;
      notifyListeners();
      return;
    }

    _lastError = null;
    _isResolving = true;
    notifyListeners();

    try {
      final staff = await _staffRepository.getStaffById(user.uid);
      if (staff != null) {
        final selected = _selectedPosition;
        _selectedPosition = null;
        if (staff.isActive &&
            selected != null &&
            !selected.matches(staff)) {
          await _rejectSession(UnknownFailure(
            'This account is ${staff.positionLabel}, not ${selected.title}. '
            'Go back and choose ${staff.positionLabel}.',
          ));
        } else if (staff.isActive) {
          _staffAccount = staff;
          _resolvedRole = staff.role;
          // The Principal and Deputy Principal options leave the Staff
          // screen once their holder has signed in. Best effort: failing to
          // record it must never block sign-in.
          if (staff.role == UserRole.principal ||
              staff.role == UserRole.deputyPrincipal) {
            unawaited(
              _positionRepository.markSlotClaimed(staff.role).catchError((_) {}),
            );
          }
        } else {
          await _rejectSession(const AccountSuspendedFailure());
        }
      } else {
        final tutor = await _tutorRepository.getTutorById(user.uid);
        if (tutor != null) {
          _tutorAccount = tutor;
          _resolvedRole = UserRole.tutor;
        }
      }

      // Signed in at the Firebase Auth level, but no matching staff or
      // tutor document exists. This is a real, reachable state, e.g. a
      // document was deleted while a device still holds a valid cached
      // session. Without this, the router sees isSignedIn == true but
      // resolvedRole == null forever and silently bounces back to the
      // login route. Signing out converts that dead end into a clear,
      // actionable message.
      if (_resolvedRole == null && _lastError == null) {
        await _rejectSession(const UnknownFailure(
          'No account found for these credentials. If you believe this '
          'is a mistake, contact the school Principal.',
        ));
      }
    } catch (e) {
      // Any unexpected failure during role resolution (permission issue,
      // transient network error, malformed document) is surfaced as
      // _lastError rather than swallowed by the stream listener.
      _lastError = e is AppFailure ? e : UnknownFailure(e.toString());
    } finally {
      _isResolving = false;
      notifyListeners();
    }
  }

  Future<void> _rejectSession(AppFailure failure) async {
    _errorAfterSignOut = failure;
    _lastError = failure;
    await _authService.signOut();
  }

  /// Tutor self-registration. Registration itself lives in
  /// TutorRepository; the authStateChanges listener above picks up the
  /// resulting sign-in and resolves the role automatically.
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
    } on AppFailure catch (e) {
      _lastError = e;
      notifyListeners();
      rethrow;
    }
  }

  /// [position] is what the person picked on the Staff screen; null for
  /// Tutor sign-in, which has no position list.
  Future<void> signIn({
    required String email,
    required String password,
    StaffPosition? position,
  }) async {
    _lastError = null;
    _errorAfterSignOut = null;
    _selectedPosition = position;
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
    _errorAfterSignOut = null;
    notifyListeners();
    await _authService.signOut();
  }

  /// Clears a stale [lastError] left over from a previous, abandoned
  /// attempt. AuthProvider outlives any one screen, so an error from a
  /// failed sign-in would otherwise reappear the next time the user opens
  /// a login screen.
  ///
  /// Call this at the point of a USER-INITIATED fresh navigation to a
  /// login screen (e.g. RoleSelectScreen's button handlers), not from the
  /// login screen's own initState/build: some arrivals at the login screen
  /// are the router's redirect reacting to an async failure, and that
  /// error is the whole reason the screen is being shown.
  void clearError() {
    _lastError = null;
    _errorAfterSignOut = null;
    notifyListeners();
  }
}
