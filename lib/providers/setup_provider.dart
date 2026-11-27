import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/setup_repository.dart';

enum SetupStatus {
  /// Asking Firestore whether the school has a Principal.
  checking,

  /// No Principal yet: the app shows ONLY the Principal registration screen.
  needsSetup,

  /// The school has a Principal: the normal app.
  ready,

  /// The answer could not be determined (offline, rules not deployed). The
  /// app shows a retry screen; it never guesses "not set up".
  error,
}

/// Tracks whether the first-run Principal registration has happened.
///
/// Once this device has seen the school as set up it remembers that, so a
/// student opening the app with no signal is not blocked by the check (the
/// marker can never be removed again).
class SetupProvider extends ChangeNotifier {
  static const _prefsKey = 'rcsn_school_setup_complete';

  final SetupRepository _repository;

  SetupProvider({SetupRepository? repository})
      : _repository = repository ?? SetupRepository() {
    check();
  }

  SetupStatus _status = SetupStatus.checking;
  Object? _error;

  SetupStatus get status => _status;
  Object? get error => _error;

  Future<void> check() async {
    _status = SetupStatus.checking;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) == true) {
        _status = SetupStatus.ready;
      } else {
        final done = await _repository
            .isSetupComplete()
            .timeout(const Duration(seconds: 15));
        if (done) {
          await prefs.setBool(_prefsKey, true);
          _status = SetupStatus.ready;
        } else {
          _status = SetupStatus.needsSetup;
        }
      }
    } catch (e) {
      _error = e;
      _status = SetupStatus.error;
    }
    notifyListeners();
  }

  /// Creates the Principal. Does NOT flip the status: the screen signs the
  /// new Principal in first and then calls [markReady], so the router does
  /// not navigate away from the setup screen mid-registration.
  Future<void> registerPrincipal({
    required String name,
    required String email,
    required String password,
  }) {
    return _repository.registerPrincipal(
      name: name,
      email: email,
      password: password,
    );
  }

  Future<void> markReady() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {}
    _status = SetupStatus.ready;
    _error = null;
    notifyListeners();
  }
}
