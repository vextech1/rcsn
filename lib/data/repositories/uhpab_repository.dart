import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';
import '../models/uhpab.dart';
import '../services/storage_service.dart';

/// Staff access to UHPAB results (`uhpab_results`) and the Bursar's
/// permission to view them (`result_clearance`). Students go through
/// UhpabService instead.
class UhpabRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storage = StorageService();

  DocumentReference<Map<String, dynamic>> _doc(String nsin) => _firestore
      .collection('uhpab_results')
      .doc(StudentNumber.bioKey(nsin));

  static String pathOf(String nsin, UhpabDocument document) =>
      'uhpab/${StudentNumber.bioKey(nsin)}/${document.id}/${document.name}';

  Stream<UhpabResults> watch(String nsin) => _doc(nsin)
      .snapshots()
      .map((s) => UhpabResults.fromRecord(s.data()));

  Future<void> saveUnit(String nsin, UhpabUnit unit) =>
      _set(nsin, 'units', unit.subjectId, unit.toMap());

  Future<void> deleteUnit(String nsin, String subjectId) =>
      _set(nsin, 'units', subjectId, FieldValue.delete());

  Future<void> saveDocument(String nsin, UhpabDocument document) =>
      _set(nsin, 'documents', document.id, document.toMap());

  /// Uploads [file] and lists it as a draft.
  Future<void> addDocument(
    String nsin,
    File file,
    String fileName,
  ) async {
    final document = UhpabDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: UhpabDocument.safeName(fileName),
      title: fileName,
    );
    await _storage.uploadFile(file: file, storagePath: pathOf(nsin, document));
    try {
      await saveDocument(nsin, document);
    } on AppFailure {
      // Not listed, so nothing would ever show or remove the file.
      await _storage.deleteFile(pathOf(nsin, document)).catchError((_) {});
      rethrow;
    }
  }

  /// Unlists first, so a failure can never leave a listed file missing.
  Future<void> deleteDocument(String nsin, UhpabDocument document) async {
    await _set(nsin, 'documents', document.id, FieldValue.delete());
    await _storage.deleteFile(pathOf(nsin, document));
  }

  /// Student numbers' keys the Bursar has allowed.
  Stream<Set<String>> watchAllowed() => _firestore
      .collection('result_clearance')
      .where('allowed', isEqualTo: true)
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id});

  Future<void> setAllowed(String nsin, bool allowed) => _write((uid) {
        return _firestore
            .collection('result_clearance')
            .doc(StudentNumber.bioKey(nsin))
            .set({
          'nsin': nsin,
          'allowed': allowed,
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Writes one course unit or document and leaves the others alone.
  Future<void> _set(String nsin, String map, String id, Object value) =>
      _write((uid) {
        return _doc(nsin).set(
          {
            'nsin': nsin,
            map: {id: value},
            'updatedBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(
            mergeFields: [
              'nsin',
              FieldPath([map, id]),
              'updatedBy',
              'updatedAt',
            ],
          ),
        );
      });

  Future<void> _write(Future<void> Function(String uid) write) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      await write(uid);
    } on FirebaseException {
      throw const CourseworkFailure(
        'Could not save. Check your connection and permissions.',
      );
    }
  }
}
