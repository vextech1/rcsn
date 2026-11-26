import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_failure.dart';
import '../../core/router/app_routes.dart';
import '../../data/models/public_post.dart';
import '../../data/repositories/public_post_repository.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_error_display.dart';
import '../../widgets/common/app_loading_indicator.dart';
import 'public_post_widgets.dart';

/// Tutor posts waiting for approval. Principal and Registrar only (the
/// route guard limits access; the rules enforce it on every write).
class PublicReviewScreen extends StatefulWidget {
  const PublicReviewScreen({super.key});

  @override
  State<PublicReviewScreen> createState() => _PublicReviewScreenState();
}

class _PublicReviewScreenState extends State<PublicReviewScreen> {
  final _repository = PublicPostRepository();
  List<PublicPost>? _posts;
  AppFailure? _loadError;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _posts = null;
    });
    try {
      final posts = await _repository.fetchPending();
      if (mounted) setState(() => _posts = posts);
    } catch (e) {
      if (mounted) setState(() => _loadError = UnknownFailure(e.toString()));
    }
  }

  Future<void> _decide(PublicPost post, PostStatus status) async {
    setState(() => _busyId = post.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.moderate(post.id, status);
      if (!mounted) return;
      setState(() => _posts = _posts?.where((p) => p.id != post.id).toList());
      messenger.showSnackBar(SnackBar(
        content: Text(status == PostStatus.published
            ? 'Published.'
            : 'Rejected.'),
      ));
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loadError != null) {
      body = AppErrorDisplay(failure: _loadError!, onRetry: _load);
    } else if (_posts == null) {
      body = const AppLoadingIndicator();
    } else if (_posts!.isEmpty) {
      body = const AppEmptyState(
        icon: Icons.fact_check,
        title: 'All caught up',
        message: 'No tutor posts are waiting for approval.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _posts!.length,
          itemBuilder: (context, i) {
            final post = _posts![i];
            final busy = _busyId == post.id;
            return Column(
              children: [
                PostCard(
                  post: post,
                  onTap: () =>
                      context.push(AppRoutes.publicPost, extra: post),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: busy
                        ? const [
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ]
                        : [
                            TextButton(
                              onPressed: () =>
                                  _decide(post, PostStatus.archived),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () =>
                                  _decide(post, PostStatus.published),
                              child: const Text('Approve'),
                            ),
                          ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Posts to review')),
      body: body,
    );
  }
}
