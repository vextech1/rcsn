import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';
import '../models/placement.dart';

/// A student's clinical placements, one document per student in
/// `student_placements/{StudentNumber.bioKey}`. It is opened by student
/// number and never listed.
class PlacementRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String nsin) => _firestore
      .collection('student_placements')
      .doc(StudentNumber.bioKey(nsin));

  /// For a placement not yet saved.
  String newId() => _firestore.collection('student_placements').doc().id;

  Stream<List<Placement>> watch(String nsin) =>
      _doc(nsin).snapshots().map((snapshot) {
        final map = snapshot.data()?['placements'] as Map? ?? const {};
        return Placement.sorted([
          for (final e in map.entries)
            Placement.fromMap(e.key as String, e.value as Map),
        ]);
      });

  Future<void> save(String nsin, Placement placement) =>
      _set(nsin, placement.id, placement.toMap());

  Future<void> delete(String nsin, String id) =>
      _set(nsin, id, FieldValue.delete());

  /// Writes one placement and leaves the others alone.
  Future<void> _set(String nsin, String id, Object value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      await _doc(nsin).set(
        {
          'nsin': nsin,
          'placements': {id: value},
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(
          mergeFields: [
            'nsin',
            FieldPath(['placements', id]),
            'updatedBy',
            'updatedAt',
          ],
        ),
      );
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not save. Check your connection and permissions.',
      );
    }
  }
}
