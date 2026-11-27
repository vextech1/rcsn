import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/errors/app_failure.dart';
import '../../data/models/public_post.dart';
import '../../data/services/storage_service.dart';
import 'public_post_widgets.dart';

/// A post's other pictures, its documents and its video or audio link.
class PostAttachments extends StatefulWidget {
  final PublicPost post;
  const PostAttachments({super.key, required this.post});

  @override
  State<PostAttachments> createState() => _PostAttachmentsState();
}

class _PostAttachmentsState extends State<PostAttachments> {
  String? _opening;

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _openDocument(String name) async {
    setState(() => _opening = name);
    try {
      final folder = await getTemporaryDirectory();
      final file = await StorageService().downloadForOffline(
        storagePath: widget.post.pathOf(name),
        localPath: '${folder.path}/${widget.post.id}_$name',
        public: true,
      );
      final result = await OpenFilex.open(file.path);
      if (mounted && result.type != ResultType.done) {
        _say('No app on this phone can open this file.');
      }
    } on AppFailure catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _openLink(String link) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (mounted && !opened) _say('Could not open the link.');
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    // The first picture is already shown at the top of the screen.
    final pictures = post.pictures.skip(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final name in pictures)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PostPicture(post: post, name: name, fit: BoxFit.fitWidth),
          ),
        for (final name in post.documents)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description),
            // Without the upload number in front.
            title: Text(name.replaceFirst(RegExp(r'^\d+_'), '')),
            trailing: _opening == name
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            onTap: _opening == null ? () => _openDocument(name) : null,
          ),
        if (post.mediaUrl case final link?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: () => _openLink(link),
              icon: const Icon(Icons.play_circle),
              label: const Text('Watch or listen'),
            ),
          ),
      ],
    );
  }
}
