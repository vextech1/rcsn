import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';

/// Private bio data entered by the Academic Registrar, kept apart from the
/// public `students` collection. The fee check compares parents' answers
/// with it.
class StudentBioRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StudentBioRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const fields = [
    'dateOfBirth',
    'district',
    'village',
    'primarySchool',
    'secondarySchool',
  ];

  /// [key] is `StudentNumber.bioKey` of the student number, or the payment
  /// code of a student without one.
  DocumentReference<Map<String, dynamic>> _doc(String key) =>
      _firestore.collection('student_bio').doc(key);

  /// Blank values if nothing has been recorded.
  Future<Map<String, String>> load(String key) async {
    try {
      final data = (await _doc(key).get()).data() ?? {};
      return {for (final f in fields) f: data[f] as String? ?? ''};
    } on FirebaseException {
      throw const FeeFailure(
        'Could not load the bio data. Check your connection and try again.',
      );
    }
  }

  Future<void> save(String key, Map<String, String> values) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      await _doc(key).set({
        for (final f in fields) f: values[f]!.trim(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      throw const FeeFailure(
        'Could not save. Check your connection and permissions.',
      );
    }
  }
}
