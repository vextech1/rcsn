import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../models/result_document.dart';

/// The school's wording for result slips and transcripts
/// (`settings/documents`).
class DocumentTemplateRepository {
  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('settings').doc('documents');

  Future<DocumentTemplate> load() async {
    try {
      return DocumentTemplate.fromMap((await _doc.get()).data());
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not load the template. Check your connection and try again.',
      );
    }
  }

  Future<void> save(Map<String, String> values) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      await _doc.set({
        for (final key in DocumentTemplate.labels.keys)
          key: (values[key] ?? '').trim(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      throw CourseworkFailure(
        'Could not save the template. Each line may have at most '
        '${DocumentTemplate.maxLength} characters.',
      );
    }
  }
}
