import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';
import '../models/attendance.dart';

/// Attendance, one document per student in
/// `student_attendance/{StudentNumber.bioKey}`. A student opens their own by
/// number; only staff may search the collection.
class AttendanceRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _records =>
      _firestore.collection('student_attendance');

  /// One student's attendance, newest class first.
  Stream<List<Attendance>> watch(String nsin) =>
      _records.doc(StudentNumber.bioKey(nsin)).snapshots().map((snapshot) {
        final units = snapshot.data()?['units'] as Map? ?? const {};
        return Attendance.sorted([
          for (final e in units.entries)
            Attendance.fromMap(e.key as String, e.value as Map),
        ]);
      });

  /// Everyone with attendance in a course unit, by student number. Staff only.
  Future<Map<String, Attendance>> forSubject(String subjectId) async {
    try {
      final found = await _records
          .where(
            FieldPath(['units', subjectId, 'year']),
            isGreaterThan: 0,
          )
          .get();
      return {
        for (final d in found.docs)
          d.data()['nsin'] as String: Attendance.fromMap(
            subjectId,
            (d.data()['units'] as Map)[subjectId] as Map,
          ),
      };
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not load the attendance. Check your connection and try again.',
      );
    }
  }

  /// Saves one course unit for several students. A null value removes it.
  Future<void> save(String subjectId, Map<String, Attendance?> byNumber) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    final entries = byNumber.entries.toList();
    try {
      // Under Firestore's limit of 500 writes in a batch.
      for (var i = 0; i < entries.length; i += 400) {
        final batch = _firestore.batch();
        for (final entry in entries.skip(i).take(400)) {
          batch.set(
            _records.doc(StudentNumber.bioKey(entry.key)),
            {
              'nsin': entry.key,
              'units': {
                subjectId: entry.value?.toMap() ?? FieldValue.delete(),
              },
              'updatedBy': uid,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(
              mergeFields: [
                'nsin',
                FieldPath(['units', subjectId]),
                'updatedBy',
                'updatedAt',
              ],
            ),
          );
        }
        await batch.commit();
      }
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not save. Check your connection and permissions.',
      );
    }
  }
}
