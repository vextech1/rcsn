import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/content_type_category.dart';
import '../../../providers/content_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/forms/app_text_field.dart';

/// Admin's content-type management screen — Section 4.3: content types
/// (Timetable, Revision Notes, etc.) are Admin-extensible at runtime,
/// not a closed list Admin is handed once. The four seeded defaults
/// (core/constants/content_types.dart) are written into Firestore on
/// first Admin setup; this screen is where Admin adds anything beyond
/// those four — new categories a tutor will then see as upload options.
///
/// PATTERN NOTE: unlike the students screen, this one uses
/// [ContentProvider] directly rather than [ContentRepository] — that
/// provider was already built (upload batch) to serve both Tutor's
/// upload flow and Admin's category management, the same dual-purpose
/// design TutorProvider uses. No new provider needed here.
///
/// Each category has a menu with Rename and Delete.
///  - Rename is always safe: uploads point at a category by id, so they
///    follow the new name straight away.
///  - Delete is refused while any upload (archived ones included) is filed
///    under the category, because deleting it would orphan those uploads.
///    The security rules cannot count documents, so the check is in
///    ContentRepository.deleteContentType.
class AdminContentTypesScreen extends StatefulWidget {
  const AdminContentTypesScreen({super.key});

  @override
  State<AdminContentTypesScreen> createState() =>
      _AdminContentTypesScreenState();
}

class _AdminContentTypesScreenState extends State<AdminContentTypesScreen> {
  final _provider = ContentProvider();
  final _nameController = TextEditingController();

  bool _isSubmitting = false;
  AppFailure? _error;
  String? _busyId;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(ContentTypeCategory type) async {
    final renamed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RenameTypeDialog(provider: _provider, type: type),
    );
    if (renamed == true) _snack('Renamed.');
  }

  Future<void> _delete(ContentTypeCategory type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${type.name}"?'),
        content: const Text(
          'Tutors will no longer see it as an upload category. A category '
          'that uploads are filed under cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyId = type.id);
    try {
      await _provider.deleteContentType(type.id);
      _snack('"${type.name}" deleted.');
    } on AppFailure catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot delete'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _addContentType() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = const UnknownFailure('Enter a name for the content type.');
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _provider.addContentType(name);
      _nameController.clear();
    } on AppFailure catch (e) {
      setState(() => _error = e);
    } catch (e) {
      setState(() => _error = UnknownFailure(e.toString()));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Content Types')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add a Content Type',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tutors will see this as an upload category, in '
                      'addition to the defaults (Timetable, Revision '
                      'Notes, and others).',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _nameController,
                      label: 'Category Name',
                      error: _error,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _addContentType,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Add Content Type'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<ContentTypeCategory>>(
      stream: _provider.watchContentTypes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingIndicator();
        }
        if (snapshot.hasError) {
          return AppErrorDisplay(
            failure: UnknownFailure(snapshot.error.toString()),
          );
        }

        final types = snapshot.data ?? [];
        if (types.isEmpty) {
          return const AppEmptyState(
            icon: Icons.category_outlined,
            title: 'No content types yet',
            message:
                'Seeded defaults appear here once Admin setup has run. '
                'Add more above as needed.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: types.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final type = types[index];
            return ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(type.name),
              trailing: _busyId == type.id
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') _rename(type);
                        if (value == 'delete') _delete(type);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

/// Rename dialog: shows the problem (too short, name already taken) inline
/// and only closes once the rename has actually been saved.
class _RenameTypeDialog extends StatefulWidget {
  final ContentProvider provider;
  final ContentTypeCategory type;

  const _RenameTypeDialog({required this.provider, required this.type});

  @override
  State<_RenameTypeDialog> createState() => _RenameTypeDialogState();
}

class _RenameTypeDialogState extends State<_RenameTypeDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  AppFailure? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.type.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name == widget.type.name) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.provider.renameContentType(id: widget.type.id, name: name);
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _error = UnknownFailure(e.toString()));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename category'),
      content: AppTextField(
        controller: _controller,
        label: 'Category Name',
        error: _error,
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
