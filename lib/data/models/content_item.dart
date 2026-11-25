import 'package:cloud_firestore/cloud_firestore.dart';

/// A single uploaded file within a Subject — a timetable, a revision note,
/// a past paper, etc.
///
/// Per Section 4.2 of the project document, ALL content types accumulate
/// as a running list by default. There is no automatic replace-and-archive
/// tied to content type — that was explicitly considered and rejected
/// during planning, because it behaves correctly for a timetable but
/// incorrectly for revision notes (which must all stay visible, not get
/// hidden behind whichever was uploaded last).
///
/// [isArchived] is therefore a plain, manually-toggled boolean — set true
/// only when the uploading tutor explicitly archives this specific file
/// from its file-options menu, and set back to false if they unarchive it.
/// Nothing in this model or its repository should ever flip this flag
/// automatically based on a new upload arriving. If future code ever does
/// that, it has silently reintroduced the exact behavior this was built to
/// avoid.
class ContentItem {
  final String id;
  final String subjectId;
  final String contentTypeId; // references a content-type category doc
  final String uploadedByTutorId;
  final String fileName;
  final String fileUrl; // Firebase Storage download URL
  final String storagePath; // Firebase Storage object path (for delete/download)
  final String fileExtension;
  final int fileSizeBytes;
  final bool isArchived;
  final String? description;
  final DateTime uploadedAt;

  const ContentItem({
    required this.id,
    required this.subjectId,
    required this.contentTypeId,
    required this.uploadedByTutorId,
    required this.fileName,
    required this.fileUrl,
    required this.storagePath,
    required this.fileExtension,
    required this.fileSizeBytes,
    required this.isArchived,
    this.description,
    required this.uploadedAt,
  });

  ContentItem copyWith({
    bool? isArchived,
    String? description,
  }) {
    return ContentItem(
      id: id,
      subjectId: subjectId,
      contentTypeId: contentTypeId,
      uploadedByTutorId: uploadedByTutorId,
      fileName: fileName,
      fileUrl: fileUrl,
      storagePath: storagePath,
      fileExtension: fileExtension,
      fileSizeBytes: fileSizeBytes,
      isArchived: isArchived ?? this.isArchived,
      description: description ?? this.description,
      uploadedAt: uploadedAt,
    );
  }

  factory ContentItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ContentItem(
      id: doc.id,
      subjectId: data['subjectId'] as String,
      contentTypeId: data['contentTypeId'] as String,
      uploadedByTutorId: data['uploadedByTutorId'] as String,
      fileName: data['fileName'] as String,
      fileUrl: data['fileUrl'] as String,
      storagePath: data['storagePath'] as String,
      fileExtension: data['fileExtension'] as String,
      fileSizeBytes: data['fileSizeBytes'] as int,
      isArchived: data['isArchived'] as bool? ?? false,
      description: data['description'] as String?,
      uploadedAt: (data['uploadedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'subjectId': subjectId,
      'contentTypeId': contentTypeId,
      'uploadedByTutorId': uploadedByTutorId,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'storagePath': storagePath,
      'fileExtension': fileExtension,
      'fileSizeBytes': fileSizeBytes,
      'isArchived': isArchived,
      'description': description,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
    };
  }
}
