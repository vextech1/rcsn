import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/public_post.dart';

/// "5 Mar 2027". Shared by the public screens.
String formatPostDate(DateTime? date) =>
    date == null ? '' : DateFormat('d MMM y').format(date);

/// A post image from a direct https link, with a neutral placeholder while
/// loading and a broken-image icon if the link does not work.
class PostImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? height;

  const PostImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: double.infinity,
      height: height,
      placeholder: (_, __) => Container(
        height: height,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => Container(
        height: height,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: Colors.black38),
      ),
    );
  }
}

/// One post in a list: category icon, title, a short preview, author, date.
class PostCard extends StatelessWidget {
  final PublicPost post;
  final VoidCallback onTap;

  const PostCard({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEvent =
        post.category == PublicCategory.event && post.eventDate != null;
    final whenText = isEvent
        ? formatPostDate(post.eventDate)
        : formatPostDate(post.createdAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.imageUrl != null)
              PostImage(url: post.imageUrl!, height: 150),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(post.category.icon,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        post.category.label.toUpperCase(),
                        style: AppTypography.overline(context),
                      ),
                      const Spacer(),
                      if (whenText.isNotEmpty)
                        Text(
                          isEvent ? 'On $whenText' : whenText,
                          style: AppTypography.caption(context),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(post.title, style: AppTypography.heading3(context)),
                  const SizedBox(height: 6),
                  Text(
                    post.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMuted(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${post.authorName} · ${post.authorRoleLabel}',
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
