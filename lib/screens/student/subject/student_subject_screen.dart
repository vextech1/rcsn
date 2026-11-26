import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../providers/student_provider.dart';
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

/// The student's read-only view of content for one subject.
///
/// Reached by tapping a subject on [StudentDashboardScreen]. Shows the
/// live main-list stream from [ContentProvider.watchMainList], filtered
/// by content type via choice chips — same pattern as
/// [TutorSubjectScreen], but without the upload/archive actions.
///
/// Tapping a file downloads it to the device and opens it in the native
/// viewer via [OpenFilex]. This is the concrete implementation of
/// Section 2.3's "student can view content" — the student sees
/// everything a tutor has uploaded into their scoped subjects.
class StudentSubjectScreen extends StatefulWidget {
  const StudentSubjectScreen({super.key});

  @override
  State<StudentSubjectScreen> createState() => _StudentSubjectScreenState();
}

class _StudentSubjectScreenState extends State<StudentSubjectScreen> {
  final _storageService = StorageService();
  String? _activeFilterId; // null = "All"

  Subject? _resolveSubject() {
    final extra = GoRouterState.of(context).extra;
    if (extra is Subject) return extra;
    return null;
  }

  Future<void> _downloadAndOpen(ContentItem item) async {
    if (!mounted) return;
    final nsin = context.read<StudentProvider>().currentStudent?.nsin;
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
      if (nsin == null) {
        throw const UnauthorizedActionFailure('Please enter your NSIN again.');
      }
      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/${item.fileName}';
      final file = await _storageService.downloadForOffline(
        storagePath: item.storagePath,
        localPath: localPath,
        studentNsin: nsin,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

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
      Navigator.of(context).pop();
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

    final trackLabel = kTrackDefinitions[subject.programType]?.label ??
        subject.programType.name;

    return Scaffold(
      appBar: AppBar(title: Text(subject.name)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '$trackLabel · Year ${subject.year}, Semester ${subject.semester}',
              style: AppTypography.caption(context),
            ),
          ),

          _ContentTypeFilterChips(
            activeFilterId: _activeFilterId,
            onFilterChanged: (id) => setState(() => _activeFilterId = id),
          ),

          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<List<ContentItem>>(
              stream: context
                  .read<ContentProvider>()
                  .watchMainList(subject.id),
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
                        'No files have been uploaded for this subject. '
                        'Check back later.',
                  );
                }

                if (items.isEmpty) {
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
                    final item = items[index];
                    return _ContentItemTile(
                      item: item,
                      onTap: () => _downloadAndOpen(item),
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
// Filter chips — same pattern as TutorSubjectScreen
// -----------------------------------------------------------------------

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
// Content item row — read-only (no archive/delete actions)
// -----------------------------------------------------------------------

class _ContentItemTile extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onTap;

  const _ContentItemTile({required this.item, required this.onTap});

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
      trailing: const Icon(Icons.download_outlined, size: 20),
    );
  }
}
