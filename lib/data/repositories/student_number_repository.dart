import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';

/// The school's student number formats, set by the Academic Registrar. Anyone
/// may read them, because students check their number before signing in.
class StudentNumberRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth? _auth;

  StudentNumberRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('settings').doc('studentNumber');

  /// Empty if no format is set.
  Future<List<String>> load() async {
    try {
      final data = (await _doc.get()).data();
      return List<String>.from(data?['formats'] as List? ?? []);
    } on FirebaseException {
      throw const UnknownFailure(
        'Could not check the student number format. Check your connection.',
      );
    }
  }

  /// Null if [input] is acceptable now.
  Future<String?> check(String input) async =>
      StudentNumber.basicError(input) ??
      StudentNumber.errorFor(input, await load());

  Future<void> save(List<String> formats) async {
    final uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    await _write(() => _doc.set({
          'formats': formats,
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
  }

  Future<void> delete() => _write(_doc.delete);

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseException {
      throw const UnknownFailure(
        'Could not save. Check your connection and permissions.',
      );
    }
  }
}
