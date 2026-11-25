import 'package:flutter/material.dart';
import '../../../core/errors/app_failure.dart';
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
/// NOT BUILT HERE, deliberately: renaming or deleting an existing
/// category. Nothing in the planning conversation specified either —
/// deleting one that's already in use by existing ContentItems would
/// orphan those items' contentTypeId, which is a real data-integrity
/// question (cascade delete? block deletion? show as "Unknown type"?)
/// that was never decided. Flagging this as a genuinely open gap rather
/// than silently deciding it by leaving delete out.
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
            );
          },
        );
      },
    );
  }
}
