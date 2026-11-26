import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/content_item.dart';
import '../models/content_type_category.dart';
import '../services/storage_service.dart';
import '../../core/authorization/tutor_authorization_checker.dart';
import '../../core/constants/content_types.dart';
import '../../core/errors/app_failure.dart';

/// Owns ContentItem uploads, archive/unarchive, and content-type
/// categories.
///
/// The one behavior this repository must never implement, stated plainly
/// because it was explicitly designed and rejected during planning: no
/// method here should EVER set isArchived=true on an existing ContentItem
/// as a side effect of a NEW upload arriving. Section 4.2 is explicit that
/// automatic replace-and-archive was considered and rejected — it works
/// for a timetable but silently hides revision notes. If a future change
/// to [uploadContent] ever archives a prior item automatically, it has
/// reintroduced a bug that was already found and fixed once.
///
/// Deliberately does NOT depend on TutorRepository directly. Tutor
/// assignment checking goes through [TutorAuthorizationChecker] instead —
/// this repository stays scoped to content concerns only. See that
/// class's doc comment for why this indirection exists rather than the
/// simpler-looking direct dependency this repository used to have.
class ContentRepository {
  final FirebaseFirestore _firestore;
  final StorageService _storageService;
  final TutorAuthorizationChecker _authChecker;

  ContentRepository({
    FirebaseFirestore? firestore,
    StorageService? storageService,
    TutorAuthorizationChecker? authChecker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storageService = storageService ?? StorageService(),
        _authChecker = authChecker ?? TutorAuthorizationChecker();

  CollectionReference<Map<String, dynamic>> get _content =>
      _firestore.collection('content_items');

  CollectionReference<Map<String, dynamic>> get _contentTypes =>
      _firestore.collection('content_types');

  /// Uploads a new file into a subject.
  ///
  /// Enforces the assignment check from Section 2.2 BEFORE any file
  /// touches Storage: a tutor who isn't assigned to [subjectId] gets
  /// [NotAssignedFailure] immediately, not after spending mobile data on
  /// an upload that would've had to be rejected anyway. This is the
  /// concrete place where [TutorAuthorizationChecker] actually gates an
  /// action, rather than assignment being a fact that's merely displayed.
  ///
  /// Always creates a NEW ContentItem — never updates or archives an
  /// existing one. Accumulate-by-default (Section 4.2) is the only
  /// behavior this method has.
  Future<ContentItem> uploadContent({
    required String subjectId,
    required String tutorId,
    required String contentTypeId,
    required File file,
    required String fileName,
    required String fileExtension,
    required int fileSizeBytes,
    String? description,
    void Function(double progress)? onProgress,
  }) async {
    final isAssigned = await _authChecker.isTutorAssignedToSubject(
      tutorId: tutorId,
      subjectId: subjectId,
    );
    if (!isAssigned) {
      throw const NotAssignedFailure();
    }

    _storageService.validateBeforeUpload(
      fileSizeBytes: fileSizeBytes,
      fileExtension: fileExtension,
    );

    // Slashes would change the path, and the storage Worker caps names at 200
    // characters (the end is kept, so the extension survives).
    var objectName =
        '${DateTime.now().millisecondsSinceEpoch}_${fileName.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_')}';
    if (objectName.length > 180) {
      objectName = objectName.substring(objectName.length - 180);
    }
    final storagePath = 'subjects/$subjectId/content/$objectName';

    final downloadUrl = await _storageService.uploadFile(
      file: file,
      storagePath: storagePath,
      onProgress: onProgress,
    );

    final actualSize = await file.length();

    final draft = ContentItem(
      id: '',
      subjectId: subjectId,
      contentTypeId: contentTypeId,
      uploadedByTutorId: tutorId,
      fileName: fileName,
      fileUrl: downloadUrl,
      storagePath: storagePath,
      fileExtension: fileExtension,
      fileSizeBytes: actualSize,
      isArchived: false, // every new upload starts unarchived — no exceptions
      description: description,
      uploadedAt: DateTime.now(),
    );

    final docRef = await _content.add(draft.toFirestore());
    final snapshot = await docRef.get();
    return ContentItem.fromFirestore(snapshot);
  }

  /// Live stream of a subject's NON-archived content, newest first —
  /// this is the "main list" per Section 4.2.
  Stream<List<ContentItem>> watchMainList(String subjectId) {
    return _content
        .where('subjectId', isEqualTo: subjectId)
        .where('isArchived', isEqualTo: false)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ContentItem.fromFirestore).toList());
  }

  /// Live stream of a subject's archived content — the Archive tab,
  /// visible to both tutor and student per Section 2.4's confirmation.
  Stream<List<ContentItem>> watchArchive(String subjectId) {
    return _content
        .where('subjectId', isEqualTo: subjectId)
        .where('isArchived', isEqualTo: true)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ContentItem.fromFirestore).toList());
  }

  /// Manual, per-file archive — the ONLY way isArchived ever becomes true.
  /// Called exclusively from a tutor tapping "Archive" in a file's options
  /// menu (Section 4.2) — never triggered automatically by this
  /// repository itself.
  Future<void> archiveItem(String contentItemId) async {
    await _content.doc(contentItemId).update({'isArchived': true});
  }

  /// Manual unarchive — returns an item to the main list. Confirmed
  /// bidirectional per Section 2.4 ("unarchive brings it back to the
  /// main list").
  Future<void> unarchiveItem(String contentItemId) async {
    await _content.doc(contentItemId).update({'isArchived': false});
  }

  Future<void> updateDescription({
    required String contentItemId,
    required String description,
  }) async {
    await _content.doc(contentItemId).update({'description': description});
  }

  /// Permanent deletion — distinct from archive, which never removes the
  /// underlying file. This removes both the Firestore record and the
  /// Storage file.
  Future<void> deleteItem({
    required String contentItemId,
    required String storagePath,
  }) async {
    await _storageService.deleteFile(storagePath);
    await _content.doc(contentItemId).delete();
  }

  // -----------------------------------------------------------------
  // Content-type categories (Section 4.3) — Admin-extensible
  // -----------------------------------------------------------------

  /// Seeds the four default content types. Called once, typically as
  /// part of Admin first-run setup — safe to call more than once since it
  /// checks for existing types first rather than blindly duplicating them.
  Future<void> seedDefaultContentTypesIfNeeded() async {
    final existing = await _contentTypes.limit(1).get();
    if (existing.docs.isNotEmpty) return; // already seeded

    final batch = _firestore.batch();
    for (final name in kSeededContentTypes) {
      final docRef = _contentTypes.doc();
      batch.set(docRef, {
        'name': name,
        'createdAt': Timestamp.now(),
      });
    }
    await batch.commit();
  }

  /// ADMIN-ONLY in intent (same convention-based caveat as
  /// TutorRepository's assignment methods — real enforcement needs
  /// Firestore security rules). Adds a new content-type category at
  /// runtime, per Section 4.3's explicit requirement that this list not
  /// be a fixed, code-baked enum.
  Future<ContentTypeCategory> addContentType(String name) async {
    final docRef = await _contentTypes.add({
      'name': name,
      'createdAt': Timestamp.now(),
    });
    final snapshot = await docRef.get();
    return ContentTypeCategory.fromFirestore(snapshot);
  }

  Stream<List<ContentTypeCategory>> watchContentTypes() {
    return _contentTypes.orderBy('createdAt').snapshots().map(
          (snap) => snap.docs.map(ContentTypeCategory.fromFirestore).toList(),
        );
  }
}
