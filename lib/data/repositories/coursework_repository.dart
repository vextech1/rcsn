import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';
import '../models/coursework.dart';

/// Coursework is kept twice, so that a student can never read a draft:
///
/// * `coursework` is the Registrar's working record, private to the
///   Registrar and Principal level.
/// * `student_results/{StudentNumber.bioKey}` holds only what has been
///   published, one document per student. Anyone who has the number can
///   open it, because students do not sign in; it cannot be listed.
class CourseworkRepository {
  final FirebaseFirestore? _injectedFirestore;
  final FirebaseAuth? _injectedAuth;

  CourseworkRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _injectedFirestore = firestore,
        _injectedAuth = auth;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _coursework =>
      _firestore.collection('coursework');

  DocumentReference<Map<String, dynamic>> _results(String nsin) => _firestore
      .collection('student_results')
      .doc(StudentNumber.bioKey(nsin));

  /// Students handled per batch: two writes each, under Firestore's 500.
  static const _batchSize = 200;

  Future<List<CourseworkEntry>> _fetch(
    String field,
    String value,
  ) async {
    try {
      final found = await _coursework.where(field, isEqualTo: value).get();
      return [for (final d in found.docs) CourseworkEntry.fromMap(d.data())];
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not load the coursework. Check your connection and try again.',
      );
    }
  }

  Future<List<CourseworkEntry>> forSubject(String subjectId) =>
      _fetch('subjectId', subjectId);

  Future<List<CourseworkEntry>> forStudent(String nsin) async =>
      _sorted(await _fetch('nsin', nsin));

  /// What the student sees, newest class first.
  Stream<List<CourseworkEntry>> watchPublished(String nsin) =>
      _results(nsin).snapshots().map((snapshot) {
        final subjects = snapshot.data()?['subjects'] as Map? ?? const {};
        return _sorted([
          for (final entry in subjects.entries)
            CourseworkEntry.fromMap({
              ...Map<String, dynamic>.from(entry.value as Map),
              'nsin': nsin,
              'subjectId': entry.key as String,
              'published': true,
            }),
        ]);
      });

  static List<CourseworkEntry> _sorted(List<CourseworkEntry> entries) =>
      entries
        ..sort((a, b) {
          if (a.year != b.year) return b.year - a.year;
          if (a.semester != b.semester) return b.semester - a.semester;
          return a.subjectName.compareTo(b.subjectName);
        });

  /// Saves without changing what students see.
  Future<void> saveDrafts(List<CourseworkEntry> entries) => _write(
        entries,
        (batch, entry, uid) => _setDraft(batch, entry, uid),
      );

  /// Saves and shows the marks to each student. Every entry must be complete.
  Future<void> publish(List<CourseworkEntry> entries) {
    assert(entries.every((e) => e.marks.isComplete));
    return _write(entries, (batch, entry, uid) {
      _setDraft(
        batch,
        entry.copyWith(published: true, pendingChanges: false),
        uid,
      );
      _setResult(batch, entry, uid, {
        'subjectName': entry.subjectName,
        'programType': entry.programType,
        'year': entry.year,
        'semester': entry.semester,
        'marks': entry.marks.values,
      });
    });
  }

  /// Hides published results from the students again. The marks are kept.
  Future<void> recall(List<CourseworkEntry> entries) =>
      _write(entries, (batch, entry, uid) {
        _setDraft(
          batch,
          entry.copyWith(published: false, pendingChanges: false),
          uid,
        );
        _setResult(batch, entry, uid, FieldValue.delete());
      });

  void _setDraft(WriteBatch batch, CourseworkEntry entry, String uid) {
    batch.set(
      _coursework
          .doc('${entry.subjectId}_${StudentNumber.bioKey(entry.nsin)}'),
      {
        'nsin': entry.nsin,
        'subjectId': entry.subjectId,
        'subjectName': entry.subjectName,
        'programType': entry.programType,
        'year': entry.year,
        'semester': entry.semester,
        'marks': entry.marks.values,
        'published': entry.published,
        'pendingChanges': entry.pendingChanges,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Replaces (or removes) one course unit in the student's results and
  /// leaves the others alone.
  void _setResult(
    WriteBatch batch,
    CourseworkEntry entry,
    String uid,
    Object value,
  ) {
    batch.set(
      _results(entry.nsin),
      {
        'nsin': entry.nsin,
        'subjects': {entry.subjectId: value},
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(
        mergeFields: [
          'nsin',
          FieldPath(['subjects', entry.subjectId]),
          'updatedBy',
          'updatedAt',
        ],
      ),
    );
  }

  Future<void> _write(
    List<CourseworkEntry> entries,
    void Function(WriteBatch, CourseworkEntry, String uid) add,
  ) async {
    final uid = (_injectedAuth ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      for (var i = 0; i < entries.length; i += _batchSize) {
        final batch = _firestore.batch();
        for (final entry in entries.skip(i).take(_batchSize)) {
          add(batch, entry, uid);
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
