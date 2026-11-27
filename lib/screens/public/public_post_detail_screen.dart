import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/user_role.dart';
import '../../core/errors/app_failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/public_post.dart';
import '../../data/repositories/public_post_repository.dart';
import '../../providers/auth_provider.dart';
import 'post_attachments.dart';
import 'public_post_widgets.dart';

/// A single public post in full. The author, or a Principal / Registrar,
/// can remove it from the public space.
class PublicPostDetailScreen extends StatefulWidget {
  final PublicPost post;

  const PublicPostDetailScreen({super.key, required this.post});

  @override
  State<PublicPostDetailScreen> createState() => _PublicPostDetailScreenState();
}

class _PublicPostDetailScreenState extends State<PublicPostDetailScreen> {
  final _repository = PublicPostRepository();
  bool _removing = false;

  Future<void> _remove({required bool asModerator}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this post?'),
        content: const Text(
          'It will no longer be visible in the public space.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _removing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (asModerator) {
        await _repository.moderate(widget.post.id, PostStatus.archived);
      } else {
        await _repository.withdraw(widget.post.id);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Post removed.')));
      if (mounted) context.pop();
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final auth = context.watch<AuthProvider>();

    final isModerator =
        auth.isUsableStaffSession && auth.resolvedRole!.canModeratePublic;
    final isAuthor = auth.firebaseUser != null &&
        auth.firebaseUser!.uid == post.authorId;
    final canRemove = isModerator || isAuthor;

    return Scaffold(
      appBar: AppBar(
        title: Text(post.category.label),
        actions: [
          if (canRemove)
            _removing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove post',
                    onPressed: () => _remove(asModerator: isModerator),
                  ),
        ],
      ),
      body: ListView(
        children: [
          if (postCover(post, height: 240) case final cover?) cover,
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.title, style: AppTypography.heading2(context)),
                const SizedBox(height: 8),
                Text(
                  '${post.authorName} · ${post.authorRoleLabel}'
                  '${post.createdAt == null ? '' : ' · ${formatPostDate(post.createdAt)}'}',
                  style: AppTypography.caption(context),
                ),
                if (post.category == PublicCategory.event &&
                    post.eventDate != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.event,
                          size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        formatPostDate(post.eventDate),
                        style: AppTypography.heading3(context),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SelectableText(post.body, style: AppTypography.body(context)),
                PostAttachments(post: post),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
