import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/user_role.dart';
import '../../core/errors/app_failure.dart';
import '../models/staff_position.dart';

/// The list of positions on the Staff screen, and which one-person slots
/// (Principal, Deputy Principal) are already taken.
///
/// Both collections are readable without signing in (the list is shown
/// before anyone has an account). Only the Principal or Deputy Principal can
/// add or remove custom positions, and a slot can only be marked taken by the
/// person who holds it: see `staff_positions` and `staff_slots` in
/// firestore.rules.
class StaffPositionRepository {
  static const maxTitleLength = 60;

  final FirebaseFirestore? _injectedFirestore;
  final FirebaseAuth? _injectedAuth;

  StaffPositionRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _injectedFirestore = firestore,
        _injectedAuth = auth;

  // Resolved lazily so merely constructing the repository never touches
  // Firebase.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _positions =>
      _firestore.collection('staff_positions');
  CollectionReference<Map<String, dynamic>> get _slots =>
      _firestore.collection('staff_slots');

  /// What the Staff screen lists: Principal and Deputy Principal until they
  /// have signed in, then Registrar, Bursar and every custom position.
  ///
  /// Never throws. If the lists cannot be read (offline, rules not updated
  /// yet) the built-in positions are shown so nobody is locked out of the
  /// sign-in screen; a taken slot only costs an extra, harmless option.
  Future<List<StaffPosition>> fetchSelectable() async {
    var principalTaken = false;
    var deputyTaken = false;
    try {
      final results = await Future.wait([
        _slots.doc(UserRole.principal.name).get(),
        _slots.doc(UserRole.deputyPrincipal.name).get(),
      ]);
      principalTaken = results[0].data()?['claimed'] == true;
      deputyTaken = results[1].data()?['claimed'] == true;
    } catch (_) {
      // Fall through with both slots shown as open.
    }

    var custom = <StaffPosition>[];
    try {
      custom = await fetchCustomPositions();
    } catch (_) {
      // Fall through with no custom positions.
    }

    return [
      if (!principalTaken) StaffPosition.principal,
      if (!deputyTaken) StaffPosition.deputyPrincipal,
      StaffPosition.registrar,
      StaffPosition.bursar,
      ...custom,
    ];
  }

  /// Custom positions only, A to Z.
  Future<List<StaffPosition>> fetchCustomPositions() async {
    final snap = await _positions.get();
    return _sorted(snap.docs.map(StaffPosition.fromFirestore));
  }

  Stream<List<StaffPosition>> watchCustomPositions() {
    return _positions.snapshots().map(
          (snap) => _sorted(snap.docs.map(StaffPosition.fromFirestore)),
        );
  }

  List<StaffPosition> _sorted(Iterable<StaffPosition> positions) {
    final list = positions.toList();
    list.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return list;
  }

  /// Adds a custom position. Rejects blanks, over-long names and anything
  /// already in the list (built-in or custom, ignoring case).
  Future<void> addPosition(String rawTitle) async {
    final title = rawTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (title.length < 2) {
      throw const StaffManagementFailure('Enter a position name.');
    }
    if (title.length > maxTitleLength) {
      throw const StaffManagementFailure(
        'That name is too long (60 characters at most).',
      );
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }

    final lower = title.toLowerCase();
    if (StaffPosition.defaults.any((p) => p.title.toLowerCase() == lower)) {
      throw StaffManagementFailure('"$title" is already in the list.');
    }

    try {
      final existing = await fetchCustomPositions();
      if (existing.any((p) => p.title.toLowerCase() == lower)) {
        throw StaffManagementFailure('"$title" is already in the list.');
      }
      await _positions.add({
        'title': title,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Removes a custom position from the list. Accounts already in it keep
  /// their access, but nobody can pick it on the Staff screen any more, so
  /// the UI warns first.
  Future<void> removePosition(String id) async {
    try {
      await _positions.doc(id).delete();
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Marks the Principal or Deputy Principal slot as taken, which hides its
  /// option on the Staff screen. Called after that person signs in; a no-op
  /// if it is already marked. Only the holder can do this (firestore.rules).
  Future<void> markSlotClaimed(UserRole role) async {
    if (role != UserRole.principal && role != UserRole.deputyPrincipal) return;
    final ref = _slots.doc(role.name);
    final snap = await ref.get();
    if (snap.data()?['claimed'] == true) return;
    await ref.set({
      'claimed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  AppFailure _mapError(Object e) {
    if (e is AppFailure) return e;
    if (e is FirebaseException && e.code == 'permission-denied') {
      return const UnauthorizedActionFailure(
        'Only the Principal or Deputy Principal can manage positions.',
      );
    }
    return const StaffManagementFailure(
      'Could not complete that action. Please try again.',
    );
  }
}
