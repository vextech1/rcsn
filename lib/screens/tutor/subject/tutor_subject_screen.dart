import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/file_size_formatter.dart';
import '../../../data/models/content_item.dart';
import '../../../data/models/content_type_category.dart';
import '../../../data/models/subject.dart';
import '../../../data/services/storage_service.dart';
import '../../../providers/content_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/common/file_type_icon.dart';

/// The tutor's view of all non-archived content for one assigned subject.
///
/// This is the third destination from the dashboard's per-subject row,
/// alongside Upload and Archive. Tapping the row itself (the ListTile
/// body, not the icon buttons) navigates here — see
/// [_AssignedSubjectTile] in [TutorDashboardScreen], which gained an
/// [onTap] for this route.
///
/// The screen shows the live main-list stream from
/// [ContentProvider.watchMainList], optionally filtered by content type
/// via a row of filter chips. Tapping a file downloads it to a local
/// temp directory and opens it in the device's native viewer via
/// [OpenFilex].
///
/// ARCHIVE ACTION: each row has an "Archive" action in its popup menu.
/// Archiving here flips [ContentItem.isArchived] → true; the item
/// immediately leaves this list (the stream updates) and appears in
/// [TutorArchiveScreen] instead. This is the concrete UI for Section
/// 4.2's manual-archive workflow — the ONLY way a file gets archived is
/// a tutor explicitly tapping this action on this screen or the archive
/// screen.
class TutorSubjectScreen extends StatefulWidget {
  const TutorSubjectScreen({super.key});

  @override
  State<TutorSubjectScreen> createState() => _TutorSubjectScreenState();
}

class _TutorSubjectScreenState extends State<TutorSubjectScreen> {
  final _storageService = StorageService();
  String? _activeFilterId; // null = "All"

  Subject? _resolveSubject() {
    final extra = GoRouterState.of(context).extra;
    if (extra is Subject) return extra;
    return null;
  }

  // -------------------------------------------------------------------
  // Download & open
  // -------------------------------------------------------------------

  Future<void> _downloadAndOpen(ContentItem item) async {
    // Show a non-dismissible indicator while the file downloads — on a
    // weak connection a 50 MB PDF could take real time, and this is
    // exactly the scenario Section 4.1 flagged for visible progress.
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text('Downloading…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/${item.fileName}';
      final file = await _storageService.downloadForOffline(
        storagePath: item.storagePath,
        localPath: localPath,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss download dialog

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? result.message
                  : 'Could not open the file.',
            ),
          ),
        );
      }
    } on AppFailure catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss download dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  // -------------------------------------------------------------------
  // Archive
  // -------------------------------------------------------------------

  Future<void> _archive(String contentItemId) async {
    try {
      await context.read<ContentProvider>().archiveItem(contentItemId);
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
        appBar: AppBar(title: const Text('Subject Content')),
        body: const AppErrorDisplay(
          failure: UnknownFailure(
            'No subject selected. Please go back and choose a subject '
            'from your dashboard.',
          ),
        ),
      );
    }

    final trackLabel =
        kTrackDefinitions[subject.programType]?.label ?? subject.programType.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload content',
            onPressed: () =>
                context.push('/tutor/upload', extra: subject),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject context header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '$trackLabel · Year ${subject.year}, Semester ${subject.semester}',
              style: AppTypography.caption(context),
            ),
          ),

          // Content type filter chips — built from the same live
          // content-types stream the upload screen's dropdown uses.
          _ContentTypeFilterChips(
            activeFilterId: _activeFilterId,
            onFilterChanged: (id) => setState(() => _activeFilterId = id),
          ),

          const Divider(height: 1),

          // Main content list
          Expanded(
            child: StreamBuilder<List<ContentItem>>(
              stream:
                  context.read<ContentProvider>().watchMainList(subject.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingIndicator();
                }

                if (snapshot.hasError) {
                  return AppErrorDisplay(
                    failure: UnknownFailure(snapshot.error.toString()),
                  );
                }

                final allItems = snapshot.data ?? [];

                // Client-side filter by content type
                final items = _activeFilterId == null
                    ? allItems
                    : allItems
                        .where((i) => i.contentTypeId == _activeFilterId)
                        .toList();

                if (allItems.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.folder_open,
                    title: 'No content yet',
                    message:
                        'Tap the upload icon above to add files to this '
                        'subject. Students will see them here once uploaded.',
                  );
                }

                if (items.isEmpty) {
                  // All items exist but none match the active filter
                  return const AppEmptyState(
                    icon: Icons.filter_list_off,
                    title: 'No matching files',
                    message:
                        'No files match the selected content type. '
                        'Try "All" or pick a different filter.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    return _ContentItemTile(
                      item: items[index],
                      onTap: () => _downloadAndOpen(items[index]),
                      onArchive: () => _archive(items[index].id),
                      onDownload: () => _downloadAndOpen(items[index]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Content type filter chips
// -----------------------------------------------------------------------

/// A horizontally-scrollable row of filter chips built from the live
/// content-types stream. The first chip is always "All" (null filter).
/// Selecting a chip filters the main content list client-side by
/// matching [ContentItem.contentTypeId].
class _ContentTypeFilterChips extends StatelessWidget {
  final String? activeFilterId;
  final ValueChanged<String?> onFilterChanged;

  const _ContentTypeFilterChips({
    required this.activeFilterId,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ContentTypeCategory>>(
      stream: context.read<ContentProvider>().watchContentTypes(),
      builder: (context, snapshot) {
        final types = snapshot.data ?? [];

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                isActive: activeFilterId == null,
                onTap: () => onFilterChanged(null),
              ),
              const SizedBox(width: 6),
              ...types.map((type) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: type.name,
                      isActive: activeFilterId == type.id,
                      onTap: () => onFilterChanged(type.id),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withAlpha(30),
      labelStyle: TextStyle(
        color: isActive ? AppColors.primary : AppColors.textMid,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: isActive ? AppColors.primary : const Color(0xFFDDDDDD),
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Content item row
// -----------------------------------------------------------------------

/// A single content-item row — icon, metadata, description, and a popup
/// menu with Archive and Download actions.
class _ContentItemTile extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDownload;

  const _ContentItemTile({
    required this.item,
    required this.onTap,
    required this.onArchive,
    required this.onDownload,
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
        style: AppTypography.body(context).copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${FileSizeFormatter.format(item.fileSizeBytes)} · $dateFormatted',
            style: AppTypography.caption(context),
          ),
          if (item.description != null && item.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(context).copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      isThreeLine: item.description != null && item.description!.isNotEmpty,
      onTap: onTap,
      trailing: PopupMenuButton<_ContentAction>(
        onSelected: (action) {
          switch (action) {
            case _ContentAction.archive:
              onArchive();
            case _ContentAction.download:
              onDownload();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ContentAction.archive,
            child: ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('Archive'),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          PopupMenuItem(
            value: _ContentAction.download,
            child: ListTile(
              leading: Icon(Icons.download_outlined),
              title: Text('Download'),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ContentAction { archive, download }
