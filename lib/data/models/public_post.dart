import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// What kind of public post this is. [name] is the stored Firestore value
/// and must match the category list in the `public_posts` rules.
enum PublicCategory {
  announcement,
  event,
  sports,
  graduation,
  performance,
  gallery,
  info,
}

extension PublicCategoryInfo on PublicCategory {
  /// Singular label, used on cards, the detail screen and the composer.
  String get label {
    switch (this) {
      case PublicCategory.announcement:
        return 'Announcement';
      case PublicCategory.event:
        return 'Calendar event';
      case PublicCategory.sports:
        return 'Sports';
      case PublicCategory.graduation:
        return 'Graduation';
      case PublicCategory.performance:
        return 'Performance';
      case PublicCategory.gallery:
        return 'Gallery';
      case PublicCategory.info:
        return 'School info';
    }
  }

  IconData get icon {
    switch (this) {
      case PublicCategory.announcement:
        return Icons.campaign;
      case PublicCategory.event:
        return Icons.event;
      case PublicCategory.sports:
        return Icons.sports_soccer;
      case PublicCategory.graduation:
        return Icons.school;
      case PublicCategory.performance:
        return Icons.theater_comedy;
      case PublicCategory.gallery:
        return Icons.photo_library;
      case PublicCategory.info:
        return Icons.info;
    }
  }
}

/// published: visible to everyone. pending: a tutor's post waiting for the
/// Principal or Registrar. archived: withdrawn or rejected.
enum PostStatus { published, pending, archived }

class PublicPost {
  final String id;
  final String title;
  final String body;
  final PublicCategory category;
  final String authorId;
  final String authorName;

  /// 'principal' | 'registrar' | 'bursar' | 'tutor'
  final String authorRole;
  final PostStatus status;
  final DateTime? createdAt;

  /// Set for calendar events.
  final DateTime? eventDate;

  /// A direct https link to an image (no file storage on the free plan).
  final String? imageUrl;

  const PublicPost({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.status,
    this.createdAt,
    this.eventDate,
    this.imageUrl,
  });

  String get authorRoleLabel {
    switch (authorRole) {
      case 'principal':
        return 'Principal';
      case 'registrar':
        return 'Registrar';
      case 'bursar':
        return 'Bursar';
      case 'tutor':
        return 'Tutor';
      default:
        return 'Staff';
    }
  }

  factory PublicPost.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;

    // Fail soft on unknown values so one odd document cannot break a
    // whole feed: unknown category shows as general info, unknown status
    // is treated as archived (hidden).
    final category = PublicCategory.values.firstWhere(
      (c) => c.name == data['category'],
      orElse: () => PublicCategory.info,
    );
    final status = PostStatus.values.firstWhere(
      (s) => s.name == data['status'],
      orElse: () => PostStatus.archived,
    );

    return PublicPost(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      category: category,
      authorId: (data['authorId'] as String?) ?? '',
      authorName: (data['authorName'] as String?) ?? 'School',
      authorRole: (data['authorRole'] as String?) ?? '',
      status: status,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      eventDate: (data['eventDate'] as Timestamp?)?.toDate(),
      imageUrl: data['imageUrl'] as String?,
    );
  }
}
