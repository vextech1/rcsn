import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/file_size_formatter.dart';
import '../../../data/models/content_item.dart';
import '../../../data/models/subject.dart';
import '../../../providers/content_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/common/file_type_icon.dart';

/// The screen where a tutor manages archived content for one subject.
///
/// Reached via [context.push(AppRoutes.tutorArchive, extra: subject)]
/// from [TutorDashboardScreen]'s per-subject archive button. The
/// [Subject] is carried in GoRouter's `extra` — same pattern as
/// [TutorUploadScreen], which carries its own Subject the same way.
///
/// Two actions are available per archived item:
/// - **Unarchive** — flips [ContentItem.isArchived] back to false. The
///   item disappears from this list and reappears on the main content
///   list, matching Section 2.4's confirmation that archive is
///   bidirectional.
/// - **Delete** — permanently removes the file from both Firebase
///   Storage and Firestore. Requires confirmation, since this cannot be
///   undone. Distinct from archive, which always preserves the
///   underlying file.
class TutorArchiveScreen extends StatefulWidget {
  const TutorArchiveScreen({super.key});

  @override
  State<TutorArchiveScreen> createState() => _TutorArchiveScreenState();
}

class _TutorArchiveScreenState extends State<TutorArchiveScreen> {
  /// Returns the [Subject] from GoRouter's extra, or null if missing or
  /// wrong type.
  Subject? _resolveSubject() {
    final extra = GoRouterState.of(context).extra;
    if (extra is Subject) return extra;
    return null;
  }

  // -------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------

  Future<void> _unarchive(String contentItemId) async {
    try {
      await context.read<ContentProvider>().unarchiveItem(contentItemId);
      // The stream updates automatically — the item vanishes from the
      // archive list and reappears on the main list. No manual state
      // update needed.
    } on AppFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _confirmAndDelete(ContentItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text(
          '"${item.fileName}" will be permanently deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<ContentProvider>().deleteItem(
            contentItemId: item.id,
            storagePath: item.storagePath,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File deleted.')),
      );
    } on AppFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subject = _resolveSubject();

    if (subject == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Archive')),
        body: const AppErrorDisplay(
          failure: UnknownFailure(
            'No subject selected. Please go back and choose a subject '
            'from your dashboard.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Archive — ${subject.name}')),
      body: StreamBuilder<List<ContentItem>>(
        stream: context.read<ContentProvider>().watchArchive(subject.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingIndicator();
          }

          if (snapshot.hasError) {
            return AppErrorDisplay(
              failure: UnknownFailure(snapshot.error.toString()),
            );
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.archive_outlined,
              title: 'No archived files',
              message:
                  'Archive a file from the main content list to see it '
                  'here. Archived files are hidden from students but '
                  'can be restored at any time.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              return _ArchiveItemTile(
                item: items[index],
                onUnarchive: () => _unarchive(items[index].id),
                onDelete: () => _confirmAndDelete(items[index]),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Private sub-widgets
// -----------------------------------------------------------------------

/// A single archived [ContentItem] row — icon, metadata, and a popup
/// menu with Unarchive and Delete actions.
///
/// Deliberately a separate widget (not an inline builder) so the row's
/// own rebuilds — e.g. after the popup menu opens — don't trigger
/// unnecessary rebuilds of the parent ListView or the StreamBuilder.
class _ArchiveItemTile extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;

  const _ArchiveItemTile({
    required this.item,
    required this.onUnarchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormatted =
        DateFormat.yMMMd().add_jm().format(item.uploadedAt);

    return ListTile(
      leading: FileTypeIcon(fileExtension: item.fileExtension, size: 32),
      title: Text(
        item.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.body(context),
      ),
      subtitle: Text(
        '${FileSizeFormatter.format(item.fileSizeBytes)} · $dateFormatted',
        style: AppTypography.caption(context),
      ),
      trailing: PopupMenuButton<_ArchiveAction>(
        onSelected: (action) {
          switch (action) {
            case _ArchiveAction.unarchive:
              onUnarchive();
            case _ArchiveAction.delete:
              onDelete();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ArchiveAction.unarchive,
            child: ListTile(
              leading: Icon(Icons.unarchive_outlined),
              title: Text('Unarchive'),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          PopupMenuItem(
            value: _ArchiveAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ArchiveAction { unarchive, delete }
