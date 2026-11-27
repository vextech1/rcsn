import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../models/timetable.dart';

/// Reads and writes `timetables`. What each caller may do is enforced by the
/// rules: the Registrar creates, edits, publishes and deletes; the Principal
/// can read everything including drafts; everyone else reads published ones.
///
/// Reads are one-shot get() calls (no live listeners) to stay inside the free
/// Spark read quota.
class TimetableRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  TimetableRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('timetables');

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    return uid;
  }

  /// Every timetable, drafts included, newest edit first. Registrar and
  /// Principal only.
  Future<List<Timetable>> fetchAll({int limit = 100}) async {
    final snap =
        await _col.orderBy('updatedAt', descending: true).limit(limit).get();
    return snap.docs.map(Timetable.fromFirestore).toList();
  }

  /// Published timetables listed for the given audiences.
  Future<List<Timetable>> fetchPublished({
    required List<TimetableAudience> audiences,
    int limit = 50,
  }) async {
    final snap = await _col
        .where('status', isEqualTo: 'published')
        .where('audience', whereIn: audiences.map((a) => a.value).toList())
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(Timetable.fromFirestore).toList();
  }

  Future<Timetable?> get(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return Timetable.fromFirestore(doc);
  }

  /// Creates a new DRAFT from [timetable] and returns its id.
  Future<String> create(Timetable timetable) async {
    final uid = _uid();
    try {
      final ref = await _col.add({
        ...timetable.toCreateMap(),
        'status': TimetableStatus.draft.name,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
      return ref.id;
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> save(Timetable timetable) async {
    final uid = _uid();
    try {
      await _col.doc(timetable.id).update({
        ...timetable.toUpdateMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> setStatus(String id, TimetableStatus status) async {
    final uid = _uid();
    try {
      await _col.doc(id).update({
        'status': status.name,
        if (status == TimetableStatus.published)
          'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _col.doc(id).delete();
    } catch (e) {
      throw _mapError(e);
    }
  }

  AppFailure _mapError(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return const UnauthorizedActionFailure(
        'Only the Registrar can change timetables.',
      );
    }
    if (e is AppFailure) return e;
    return const UnknownFailure('Something went wrong. Please try again.');
  }
}
