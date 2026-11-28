import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';
import '../models/discipline_case.dart';

/// Disciplinary cases are kept twice, so that a student reads only what has
/// been marked visible:
///
/// * `discipline_cases` is the school's record, private to the Registrar and
///   Principal level.
/// * `student_discipline/{StudentNumber.bioKey}` holds the visible cases, one
///   document per student, opened by student number and never listed.
class DisciplineRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _cases =>
      _firestore.collection('discipline_cases');

  DocumentReference<Map<String, dynamic>> _visible(String nsin) => _firestore
      .collection('student_discipline')
      .doc(StudentNumber.bioKey(nsin));

  /// For a case not yet saved.
  String newId() => _cases.doc().id;

  /// Every case against a student. Staff only.
  Stream<List<DisciplineCase>> watch(String nsin) => _cases
      .where('nsin', isEqualTo: nsin)
      .snapshots()
      .map((found) => DisciplineCase.sorted([
            for (final d in found.docs)
              DisciplineCase.fromMap(d.id, nsin, d.data()),
          ]));

  /// What the student sees.
  Stream<List<DisciplineCase>> watchVisible(String nsin) =>
      _visible(nsin).snapshots().map((snapshot) {
        final cases = snapshot.data()?['cases'] as Map? ?? const {};
        return DisciplineCase.sorted([
          for (final e in cases.entries)
            DisciplineCase.fromMap(e.key as String, nsin, e.value as Map),
        ]);
      });

  /// Saves the case and, in the same step, shows it to or hides it from the
  /// student. Cases are never deleted.
  Future<void> save(DisciplineCase item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    final stamp = {
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch()
      ..set(_cases.doc(item.id), {
        'nsin': item.nsin,
        ...item.toStudentMap(),
        'visible': item.visible,
        ...stamp,
      })
      ..set(
        _visible(item.nsin),
        {
          'nsin': item.nsin,
          'cases': {
            item.id: item.visible ? item.toStudentMap() : FieldValue.delete(),
          },
          ...stamp,
        },
        SetOptions(
          mergeFields: [
            'nsin',
            FieldPath(['cases', item.id]),
            'updatedBy',
            'updatedAt',
          ],
        ),
      );
    try {
      await batch.commit();
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not save. Check your connection and permissions.',
      );
    }
  }
}
