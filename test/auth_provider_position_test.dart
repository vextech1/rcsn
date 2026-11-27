import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/core/constants/user_role.dart';
import 'package:rcsn_mobile_app/core/errors/app_failure.dart';
import 'package:rcsn_mobile_app/data/models/staff_account.dart';
import 'package:rcsn_mobile_app/data/models/staff_position.dart';
import 'package:rcsn_mobile_app/data/models/tutor_account.dart';
import 'package:rcsn_mobile_app/data/repositories/staff_repository.dart';
import 'package:rcsn_mobile_app/data/repositories/tutor_repository.dart';
import 'package:rcsn_mobile_app/data/services/auth_service.dart';
import 'package:rcsn_mobile_app/providers/auth_provider.dart';

// Fakes that behave like Firebase for the one thing under test: signing in
// emits an auth-state event, and signing out emits null.

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthService implements AuthService {
  final _controller = StreamController<User?>.broadcast();
  User? _current;

  /// email -> uid (every password is accepted; passwords are not under test)
  final Map<String, String> accounts;
  _FakeAuthService(this.accounts);

  @override
  User? get currentUser => _current;

  @override
  Stream<User?> get authStateChanges => _controller.stream;

  @override
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final uid = accounts[email];
    if (uid == null) throw const InvalidCredentialsFailure();
    final user = _FakeUser(uid);
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStaffRepository implements StaffRepository {
  final Map<String, StaffAccount> byUid;
  _FakeStaffRepository(this.byUid);

  @override
  Future<StaffAccount?> getStaffById(String uid) async => byUid[uid];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTutorRepository implements TutorRepository {
  final Map<String, TutorAccount> byUid;
  _FakeTutorRepository(this.byUid);

  @override
  Future<TutorAccount?> getTutorById(String tutorId) async => byUid[tutorId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StaffAccount _staff(String id, UserRole role) => StaffAccount(
      id: id,
      name: 'Test $id',
      email: '$id@rcsn.test',
      role: role,
      status: StaffStatus.active,
    );

final _tutor = TutorAccount(
  id: 'tutor1',
  name: 'Test Tutor',
  email: 'tutor1@rcsn.test',
  status: AccountStatus.active,
  registeredAt: DateTime(2026),
);

AuthProvider _provider() => AuthProvider(
      authService: _FakeAuthService({
        'bursar@rcsn.test': 'bursar1',
        'registrar@rcsn.test': 'registrar1',
        'tutor@rcsn.test': 'tutor1',
      }),
      staffRepository: _FakeStaffRepository({
        'bursar1': _staff('bursar1', UserRole.bursar),
        'registrar1': _staff('registrar1', UserRole.registrar),
      }),
      tutorRepository: _FakeTutorRepository({'tutor1': _tutor}),
    );

Future<void> _settle() => pumpEventQueue(times: 50);

void main() {
  test('Bursar signing in through Registrar is rejected and signed out',
      () async {
    final auth = _provider();
    await auth.signIn(
      email: 'bursar@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
      position: StaffPosition.registrar,
    );
    await _settle();

    expect(auth.resolvedRole, isNull);
    expect(auth.isUsableStaffSession, isFalse);
    expect(auth.isSignedIn, isFalse);
    expect(auth.lastError?.message, contains('Bursar'));
  });

  test('Registrar signing in through Bursar is rejected', () async {
    final auth = _provider();
    await auth.signIn(
      email: 'registrar@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
      position: StaffPosition.bursar,
    );
    await _settle();

    expect(auth.resolvedRole, isNull);
    expect(auth.isSignedIn, isFalse);
  });

  test('Bursar signing in through Bursar is accepted', () async {
    final auth = _provider();
    await auth.signIn(
      email: 'bursar@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
      position: StaffPosition.bursar,
    );
    await _settle();

    expect(auth.resolvedRole, UserRole.bursar);
    expect(auth.isUsableStaffSession, isTrue);
  });

  test('Tutor signing in through a staff position is rejected', () async {
    final auth = _provider();
    await auth.signIn(
      email: 'tutor@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
      position: StaffPosition.registrar,
    );
    await _settle();

    expect(auth.resolvedRole, isNull,
        reason: 'a tutor account must not be accepted at the staff door');
    expect(auth.isSignedIn, isFalse);
  });

  test('Tutor signing in through a staff position says it is a Tutor',
      () async {
    final auth = _provider();
    await auth.signIn(
      email: 'tutor@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
      position: StaffPosition.registrar,
    );
    await _settle();

    expect(auth.lastError?.message, contains('Tutor'));
  });

  test('Tutor signing in through the staff login with no position is rejected',
      () async {
    final auth = _provider();
    await auth.signIn(
      email: 'tutor@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
    );
    await _settle();

    expect(auth.resolvedRole, isNull);
    expect(auth.isSignedIn, isFalse);
  });

  test('Staff signing in through the Tutor login is rejected and signed out',
      () async {
    final auth = _provider();
    await auth.signIn(
      email: 'bursar@rcsn.test',
      password: 'x',
      door: LoginDoor.tutor,
    );
    await _settle();

    expect(auth.resolvedRole, isNull);
    expect(auth.isUsableStaffSession, isFalse);
    expect(auth.isSignedIn, isFalse);
    expect(auth.lastError?.message, contains('Bursar'));
  });

  test('Tutor signing in through the Tutor login is accepted', () async {
    final auth = _provider();
    await auth.signIn(
      email: 'tutor@rcsn.test',
      password: 'x',
      door: LoginDoor.tutor,
    );
    await _settle();

    expect(auth.resolvedRole, UserRole.tutor);
    expect(auth.isUsableTutorSession, isTrue);
  });

  test('Staff signing in through the staff login with no position is accepted',
      () async {
    final auth = _provider();
    await auth.signIn(
      email: 'registrar@rcsn.test',
      password: 'x',
      door: LoginDoor.staff,
    );
    await _settle();

    expect(auth.resolvedRole, UserRole.registrar);
    expect(auth.isUsableStaffSession, isTrue);
  });

  test('A failed sign-in does not leave its door behind for the next one',
      () async {
    final auth = _provider();
    await expectLater(
      auth.signIn(
        email: 'nobody@rcsn.test',
        password: 'x',
        door: LoginDoor.staff,
        position: StaffPosition.registrar,
      ),
      throwsA(isA<InvalidCredentialsFailure>()),
    );

    // A sign-in with no door (like a restored session or a new tutor
    // registration) must not be judged by the failed attempt before it.
    await auth.signIn(email: 'tutor@rcsn.test', password: 'x');
    await _settle();

    expect(auth.resolvedRole, UserRole.tutor);
    expect(auth.isUsableTutorSession, isTrue);
  });
}
