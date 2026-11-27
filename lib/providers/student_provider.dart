import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repositories/student_number_repository.dart';
import '../data/repositories/student_repository.dart';
import '../data/models/student_record.dart';
import '../data/models/tutor_account.dart' show AccountStatus;
import '../core/utils/student_number.dart';
import '../core/errors/app_failure.dart';

/// Holds the current Student "session" — which is deliberately NOT the
/// same kind of thing as AuthProvider's session.
///
/// Per Section 2.3, there is no password and no Firebase Auth involved
/// for students at all — entering a valid NSIN is the entire access
/// mechanism.
///
/// PERSISTENCE (explicit product decision, not a default): the session
/// survives app close/restart via shared_preferences — a student who
/// enters their NSIN once should not have to re-enter it every time they
/// open the app. This was a real, deliberately-made decision, not an
/// implementation default — an earlier draft of this provider had no
/// persistence at all, flagged specifically because silently caching an
/// NSIN across restarts was a real product behavior that hadn't been
/// discussed yet. It has now been discussed and confirmed.
///
/// THE BORROWED-PHONE PROBLEM this persistence creates, and why
/// [clearSession] exists: some students don't have their own smartphone
/// and borrow a classmate's to check academic info (e.g. a Year 1
/// student borrowing a Year 2 student's phone to see a timetable).
/// Persistence alone would mean the borrower sees the PHONE OWNER's data,
/// not their own — the app has no way to know a different person is now
/// holding the device. [clearSession] is the only mechanism that fixes
/// this: it's not a convenience feature, it's what makes persistence safe
/// to have at all in a shared-device context. Per explicit product
/// decision: this action lives in Settings only (not surfaced on the
/// dashboard itself) and requires confirmation before clearing — both
/// deliberately chosen to protect a student's OWN long-running session
/// from being cleared by accident, even though that means a borrower has
/// to actively go find it. The settings screen calling [clearSession]
/// should confirm with the user before calling it — this method itself
/// does not re-confirm, that's a UI-layer responsibility.
class StudentProvider extends ChangeNotifier {
  static const String _prefsKeyNsin = 'student_session_nsin';

  final StudentRepository _repository;
  SharedPreferences? _prefs;

  StudentProvider({StudentRepository? repository})
      : _repository = repository ?? StudentRepository() {
    _restoreSession();
  }

  StudentRecord? _currentStudent;
  bool _isSearching = false;
  bool _isRestoring = true;
  AppFailure? _lastError;

  StudentRecord? get currentStudent => _currentStudent;
  bool get isSearching => _isSearching;

  /// True while checking shared_preferences for a previously-saved NSIN
  /// on app startup. The student-facing entry screen should show a brief
  /// loading state (not the NSIN input form) while this is true, to
  /// avoid a flash of the input screen before a persisted session loads.
  bool get isRestoring => _isRestoring;

  AppFailure? get lastError => _lastError;
  bool get hasActiveSession => _currentStudent != null;

  /// True once a lookup has succeeded AND the found record's status is
  /// active. A suspended or terminated-course student should not be
  /// treated as having a usable session even though their NSIN is
  /// genuinely valid and was genuinely found — screens should check
  /// this, not just [hasActiveSession].
  bool get isUsableSession =>
      _currentStudent != null &&
      _currentStudent!.status == AccountStatus.active;

  /// On provider creation, checks shared_preferences for a previously
  /// saved NSIN and re-resolves it against Firestore — NOT just trusting
  /// the cached StudentRecord data, since the student's status or
  /// academic scope could have changed since it was last saved (e.g.
  /// Admin suspended them, or advanced them to a new semester). The
  /// saved value is only ever the NSIN string itself; the actual record
  /// is always re-fetched fresh.
  Future<void> _restoreSession() async {
    _prefs = await SharedPreferences.getInstance();
    final savedNsin = _prefs?.getString(_prefsKeyNsin);

    if (savedNsin != null && savedNsin.isNotEmpty) {
      try {
        final record = await _repository.findByNsin(savedNsin);
        _currentStudent = record; // null if it no longer resolves — e.g.
        // Admin removed the record; session silently ends rather than
        // showing stale data.
      } catch (_) {
        _currentStudent = null;
      }
    }

    _isRestoring = false;
    notifyListeners();
  }

  /// The Section 2.3 entry point. Validates FORMAT locally first (fast,
  /// no network call for an obviously malformed entry — see
  /// StudentNumber's own doc comments on why format and existence are
  /// checked separately), then performs the actual existence lookup
  /// against Firestore via StudentRepository. An NSIN that doesn't
  /// resolve to any record — because Admin is the only source of valid
  /// NSINs and this one was never issued — is rejected via
  /// [NsinNotFoundFailure], same as before persistence was added.
  ///
  /// On success, saves the NSIN to shared_preferences so the session
  /// survives app restart.
  Future<void> searchByNsin(String rawInput) async {
    _lastError = null;

    final formatError = StudentNumber.basicError(rawInput);
    if (formatError != null) {
      _lastError = UnknownFailure(formatError);
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      // The Registrar's format, if one is set.
      final mismatch = await StudentNumberRepository().check(rawInput);
      if (mismatch != null) throw UnknownFailure(mismatch);
      final record = await _repository.findByNsin(rawInput);
      if (record == null) {
        _lastError = const NsinNotFoundFailure();
        _currentStudent = null;
      } else {
        _currentStudent = record;
        await _persistNsin(StudentNumber.normalize(rawInput));
      }
    } catch (e) {
      _lastError = e is AppFailure ? e : const UnknownFailure();
      _currentStudent = null;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> _persistNsin(String nsin) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefsKeyNsin, nsin);
  }

  /// Clears the current session, including the persisted NSIN — this is
  /// the ONLY way the persisted value is ever removed. Per the class doc
  /// above: called exclusively from a Settings screen, after the UI has
  /// already confirmed the action with the student. After clearing, the
  /// app returns to NSIN entry, matching the "clear NSIN → back to input
  /// NSIN to continue" flow this was designed for.
  Future<void> clearSession() async {
    _currentStudent = null;
    _lastError = null;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_prefsKeyNsin);
    notifyListeners();
  }
}
