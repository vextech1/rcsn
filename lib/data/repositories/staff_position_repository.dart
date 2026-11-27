import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../models/staff_position.dart';

/// The list of positions on the Staff screen.
///
/// The collection is readable without signing in (the list is shown before
/// anyone has an account). Only the Principal or Deputy Principal can add or
/// remove custom positions: see `staff_positions` in firestore.rules.
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

  /// What the Staff screen lists: Principal, Deputy Principal, Registrar and
  /// Bursar, then every custom position. The built-in four always stay on the
  /// list.
  ///
  /// Never throws. If the custom positions cannot be read (offline, rules not
  /// updated yet) the built-in positions are still shown, so nobody is locked
  /// out of the sign-in screen.
  Future<List<StaffPosition>> fetchSelectable() async {
    var custom = <StaffPosition>[];
    try {
      custom = await fetchCustomPositions();
    } catch (_) {
      // Fall through with no custom positions.
    }
    return [...StaffPosition.defaults, ...custom];
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
