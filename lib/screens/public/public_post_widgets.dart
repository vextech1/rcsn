import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/public_post.dart';
import '../../data/services/storage_service.dart';

/// "5 Mar 2027". Shared by the public screens.
String formatPostDate(DateTime? date) =>
    date == null ? '' : DateFormat('d MMM y').format(date);

/// An uploaded picture. Unpublished ones need the viewer's sign-in.
class PostPicture extends StatefulWidget {
  final PublicPost post;
  final String name;
  final BoxFit fit;
  final double? height;

  const PostPicture({
    super.key,
    required this.post,
    required this.name,
    this.fit = BoxFit.cover,
    this.height,
  });

  @override
  State<PostPicture> createState() => _PostPictureState();
}

class _PostPictureState extends State<PostPicture> {
  late final Future<Map<String, String>> _headers =
      widget.post.status == PostStatus.published
          ? Future.value(<String, String>{})
          : StorageService().optionalHeaders();

  @override
  Widget build(BuildContext context) {
    final String url;
    try {
      url = StorageService()
          .urlFor(widget.post.pathOf(widget.name))
          .toString();
    } on Exception {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Icon(Icons.broken_image)),
      );
    }
    return FutureBuilder<Map<String, String>>(
      future: _headers,
      builder: (context, snapshot) => snapshot.hasData
          ? PostImage(
              url: url,
              headers: snapshot.data,
              fit: widget.fit,
              height: widget.height,
            )
          : SizedBox(height: widget.height),
    );
  }
}

/// The picture that stands for a post in lists, or null if it has none.
Widget? postCover(PublicPost post, {double? height}) {
  final pictures = post.pictures;
  if (pictures.isNotEmpty) {
    return PostPicture(
      key: ValueKey(post.pathOf(pictures.first)),
      post: post,
      name: pictures.first,
      height: height,
    );
  }
  final link = post.imageUrl;
  return link == null ? null : PostImage(url: link, height: height);
}

/// A post image from an https address, with a neutral placeholder while
/// loading and a broken-image icon if the link does not work.
class PostImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? height;
  final Map<String, String>? headers;

  const PostImage({
    super.key,
    required this.url,
    this.headers,
    this.fit = BoxFit.cover,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
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
            if (postCover(post, height: 150) case final cover?) cover,
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
