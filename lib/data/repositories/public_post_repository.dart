import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/errors/app_failure.dart';
import '../models/public_post.dart';

/// Reads and writes the Public Space (`public_posts`).
///
/// Reads use one-shot get() with pull-to-refresh, not live listeners: the
/// public side can have many anonymous readers on the free Spark plan's
/// daily read quota, and a feed does not need to update in real time.
/// What each caller may do is enforced by the `public_posts` rules.
class PublicPostRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  PublicPostRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('public_posts');

  /// Latest published posts, optionally for one category.
  Future<List<PublicPost>> fetchPublished({
    PublicCategory? category,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query =
        _posts.where('status', isEqualTo: 'published');
    if (category != null) {
      query = query.where('category', isEqualTo: category.name);
    }
    final snap =
        await query.orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map(PublicPost.fromFirestore).toList();
  }

  /// Published calendar events from today onward, soonest first.
  Future<List<PublicPost>> fetchUpcomingEvents({int limit = 50}) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final snap = await _posts
        .where('status', isEqualTo: 'published')
        .where('category', isEqualTo: PublicCategory.event.name)
        .where(
          'eventDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
        )
        .orderBy('eventDate')
        .limit(limit)
        .get();
    return snap.docs.map(PublicPost.fromFirestore).toList();
  }

  /// Tutor posts waiting for approval. Principal / Registrar only.
  Future<List<PublicPost>> fetchPending({int limit = 50}) async {
    final snap = await _posts
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(PublicPost.fromFirestore).toList();
  }

  /// Creates a post. Staff posts go live immediately; a tutor's post is
  /// stored as pending (the rules require exactly that).
  Future<void> create({
    required PublicCategory category,
    required String title,
    required String body,
    required String authorName,
    required String authorRole,
    required bool publishDirectly,
    DateTime? eventDate,
    String? imageUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in to post.');
    }

    final data = <String, dynamic>{
      'title': title,
      'body': body,
      'category': category.name,
      'authorId': uid,
      'authorName': authorName,
      'authorRole': authorRole,
      'status': publishDirectly ? 'published' : 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (eventDate != null) data['eventDate'] = Timestamp.fromDate(eventDate);
    if (imageUrl != null && imageUrl.isNotEmpty) data['imageUrl'] = imageUrl;

    try {
      await _posts.add(data);
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Principal / Registrar: publish or archive any post.
  Future<void> moderate(String postId, PostStatus status) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    try {
      await _posts.doc(postId).update({
        'status': status.name,
        'reviewedBy': uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// An author withdrawing their own post.
  Future<void> withdraw(String postId) async {
    try {
      await _posts.doc(postId).update({'status': PostStatus.archived.name});
    } catch (e) {
      throw _mapError(e);
    }
  }

  AppFailure _mapError(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return const UnauthorizedActionFailure(
        'You do not have permission to do that.',
      );
    }
    if (e is AppFailure) return e;
    return const UnknownFailure('Something went wrong. Please try again.');
  }
}
