import 'package:cloud_firestore/cloud_firestore.dart';

/// A content-type category (Timetable, Revision Notes, etc.) as a real
/// Firestore document.
///
/// This is the runtime counterpart to kSeededContentTypes
/// (core/constants/content_types.dart). That constant list is used ONCE,
/// on first Admin setup, to seed these four documents into Firestore.
/// After that, this collection — not the constant — is the source of
/// truth, since Section 4.3 requires Admin to be able to add new
/// categories at runtime without a code change or app update.
class ContentTypeCategory {
  final String id;
  final String name;
  final DateTime createdAt;

  const ContentTypeCategory({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory ContentTypeCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ContentTypeCategory(
      id: doc.id,
      name: data['name'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
