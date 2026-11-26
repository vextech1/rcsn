import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/upload_rules.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/file_size_formatter.dart';
import '../../../data/models/content_type_category.dart';
import '../../../data/models/subject.dart';
import '../../../data/services/storage_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/content_provider.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/common/file_type_icon.dart';
import '../../../widgets/common/upload_progress_indicator.dart';
import '../../../widgets/forms/app_text_field.dart';

/// The screen where a tutor uploads a new file into an assigned subject.
///
/// Reached via [context.push(AppRoutes.tutorUpload, extra: subject)] from
/// [TutorDashboardScreen]'s per-subject upload button. The [Subject] is
/// carried in GoRouter's `extra` — this screen does not re-derive which
/// subject the tutor meant; it trusts the caller to have passed the right
/// one, since the dashboard only renders upload buttons on rows the
/// assignments stream already produced.
///
/// Upload guard (assignment check) is enforced inside
/// [ContentRepository.uploadContent] via [TutorAuthorizationChecker] —
/// this screen does not duplicate that check. If the repository throws
/// [NotAssignedFailure], this screen displays it the same way it displays
/// any other upload failure, so a tutor who somehow reached this screen
/// without a valid assignment still gets a clear message rather than a
/// silent failure.
///
/// PROGRESS: [UploadProgressIndicator] replaces the form body during
/// upload, driven by [ContentProvider.uploadProgress] (0.0–1.0). This is
/// the concrete UI for Section 4.1's requirement that uploads at the
/// 95 MB cap must show visible progress — not optional, per that
/// section's note on weak mobile connections.
class TutorUploadScreen extends StatefulWidget {
  const TutorUploadScreen({super.key});

  @override
  State<TutorUploadScreen> createState() => _TutorUploadScreenState();
}

class _TutorUploadScreenState extends State<TutorUploadScreen> {
  final _descriptionController = TextEditingController();
  final _storageService = StorageService();

  ContentTypeCategory? _selectedType;
  File? _selectedFile;
  String? _fileName;
  String? _fileExtension;
  int? _fileSizeBytes;
  AppFailure? _localError;
  AppFailure? _uploadError;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // File picking + local validation
  // -------------------------------------------------------------------

  Future<void> _pickFile() async {
    _localError = null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: UploadRules.allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return; // user cancelled

    final picked = result.files.single;
    if (picked.path == null) {
      setState(() {
        _localError =
            const UnknownFailure('Could not access the selected file.');
      });
      return;
    }

    final file = File(picked.path!);
    final extension = picked.extension ?? '';
    final size = picked.size;

    // Local validation — fast, offline, no network call. Same rules
    // [ContentRepository.uploadContent] enforces server-side; this just
    // catches the error before spending mobile data on a doomed upload.
    try {
      _storageService.validateBeforeUpload(
        fileSizeBytes: size,
        fileExtension: extension,
      );
    } on AppFailure catch (e) {
      setState(() {
        _localError = e;
        _selectedFile = null;
        _fileName = null;
        _fileExtension = null;
        _fileSizeBytes = null;
      });
      return;
    }

    setState(() {
      _selectedFile = file;
      _fileName = picked.name;
      _fileExtension = extension;
      _fileSizeBytes = size;
      _localError = null;
    });
  }

  void _clearFile() {
    setState(() {
      _selectedFile = null;
      _fileName = null;
      _fileExtension = null;
      _fileSizeBytes = null;
      _localError = null;
    });
  }

  // -------------------------------------------------------------------
  // Upload
  // -------------------------------------------------------------------

  bool get _canUpload =>
      _selectedType != null &&
      _selectedFile != null &&
      !_isSubmitting;

  Future<void> _upload() async {
    if (!_canUpload) return;

    final contentProvider = context.read<ContentProvider>();
    final auth = context.read<AuthProvider>();
    final subject = _resolveSubject();

    if (subject == null || auth.firebaseUser == null) return;

    setState(() {
      _isSubmitting = true;
      _uploadError = null;
    });

    try {
      await contentProvider.uploadContent(
        subjectId: subject.id,
        tutorId: auth.firebaseUser!.uid,
        contentTypeId: _selectedType!.id,
        file: _selectedFile!,
        fileName: _fileName!,
        fileExtension: _fileExtension!,
        fileSizeBytes: _fileSizeBytes!,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded successfully.')),
      );
      Navigator.of(context).pop();
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadError = e;
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadError = UnknownFailure(e.toString());
        _isSubmitting = false;
      });
    }
  }

  /// Returns the [Subject] this screen was navigated to with, or null if
  /// the route's `extra` is missing or the wrong type — which should
  /// only happen if someone deep-links directly to /tutor/upload without
  /// passing through the dashboard first.
  Subject? _resolveSubject() {
    final extra = GoRouterState.of(context).extra;
    if (extra is Subject) return extra;
    return null;
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subject = _resolveSubject();
    final contentProvider = context.watch<ContentProvider>();

    // If the upload is in flight, the entire body becomes the progress
    // indicator — replacing the form rather than overlaying it makes it
    // visually unambiguous that the upload is happening and the form's
    // fields are not interactable.
    if (contentProvider.isUploading && _isSubmitting) {
      return Scaffold(
        appBar: AppBar(title: Text(subject?.name ?? 'Upload')),
        body: UploadProgressIndicator(
          progress: contentProvider.uploadProgress,
          totalBytes: _fileSizeBytes ?? 0,
          fileName: _fileName ?? '',
          onCancel: null, // upload cancellation is not yet supported
          // at the service level — see StorageService.uploadFile, which
          // does not expose a cancel mechanism for the underlying
          // Firebase Storage upload task.
        ),
      );
    }

    if (subject == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Upload')),
        body: const AppErrorDisplay(
          failure: UnknownFailure(
            'No subject selected. Please go back and choose a subject '
            'from your dashboard.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(subject.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------------------------------------------------------
            // Section 1 — Content type
            // ---------------------------------------------------------
            _SectionLabel(text: 'Content Type'),
            const SizedBox(height: 8),
            _ContentTypeDropdown(
              selectedType: _selectedType,
              onChanged: (type) => setState(() => _selectedType = type),
            ),

            const SizedBox(height: 24),

            // ---------------------------------------------------------
            // Section 2 — File
            // ---------------------------------------------------------
            _SectionLabel(text: 'File'),
            const SizedBox(height: 8),
            if (_selectedFile != null)
              _FilePreviewCard(
                fileName: _fileName!,
                fileExtension: _fileExtension!,
                fileSizeBytes: _fileSizeBytes!,
                onRemove: _clearFile,
              )
            else
              _FilePickerButton(
                onTap: _pickFile,
                isDisabled: _isSubmitting,
              ),
            if (_localError != null) ...[
              const SizedBox(height: 8),
              AppInlineError(failure: _localError!),
            ],

            const SizedBox(height: 24),

            // ---------------------------------------------------------
            // Section 3 — Description (optional)
            // ---------------------------------------------------------
            _SectionLabel(text: 'Description (optional)'),
            const SizedBox(height: 8),
            AppTextField(
              controller: _descriptionController,
              label: 'E.g. "Week 3 lecture slides"',
            ),

            const SizedBox(height: 32),

            // ---------------------------------------------------------
            // Upload button + error
            // ---------------------------------------------------------
            FilledButton.icon(
              onPressed: _canUpload ? _upload : null,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload'),
            ),
            if (_uploadError != null) ...[
              const SizedBox(height: 12),
              AppInlineError(failure: _uploadError!),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Private sub-widgets — scoped to this file, not shared, because they
// are specific to the upload screen's layout and have no reuse elsewhere.
// -----------------------------------------------------------------------

/// A small, uppercase section heading — keeps the three form sections
/// visually grouped without needing Card or ExpansionTile containers.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMid,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// The live content-type dropdown, backed by [ContentProvider].
/// Renders appropriate empty/loading states rather than showing an
/// empty dropdown with no explanation.
class _ContentTypeDropdown extends StatelessWidget {
  final ContentTypeCategory? selectedType;
  final ValueChanged<ContentTypeCategory?> onChanged;

  const _ContentTypeDropdown({
    required this.selectedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ContentTypeCategory>>(
      stream: context.read<ContentProvider>().watchContentTypes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: AppLoadingIndicator(),
          );
        }

        if (snapshot.hasError) {
          return AppInlineError(
            failure: UnknownFailure(snapshot.error.toString()),
          );
        }

        final types = snapshot.data ?? [];
        if (types.isEmpty) {
          return const AppEmptyState(
            icon: Icons.category_outlined,
            title: 'No content types',
            message:
                'Content types have not been set up yet. Contact Admin '
                'to configure them under Content Types.',
          );
        }

        return DropdownButtonFormField<ContentTypeCategory>(
          initialValue: selectedType,
          decoration: const InputDecoration(
            labelText: 'Select a content type',
            border: OutlineInputBorder(),
          ),
          isExpanded: true,
          items: types
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.name),
                  ))
              .toList(),
          onChanged: onChanged,
          validator: (v) => v == null ? 'Select a content type' : null,
        );
      },
    );
  }
}

/// The "Select File" button, shown before any file has been picked.
/// Styled as an outlined, dashed-border area rather than a plain button,
/// to make the drop zone / picker affordance visually clear.
class _FilePickerButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDisabled;

  const _FilePickerButton({
    required this.onTap,
    required this.isDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primaryLight.withAlpha(100),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          borderRadius: BorderRadius.circular(12),
          color: AppColors.primary.withAlpha(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.upload_file,
              size: 40,
              color: AppColors.primaryLight.withAlpha(180),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap to select a file',
              style: TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Images, PDF, Excel, or Word — up to 95 MB',
              style: TextStyle(fontSize: 12, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview card shown after a file has been picked — icon, name,
/// size, and a remove button so the tutor can pick a different file
/// without having to back all the way out of the screen.
class _FilePreviewCard extends StatelessWidget {
  final String fileName;
  final String fileExtension;
  final int fileSizeBytes;
  final VoidCallback onRemove;

  const _FilePreviewCard({
    required this.fileName,
    required this.fileExtension,
    required this.fileSizeBytes,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFDDDDDD)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FileTypeIcon(fileExtension: fileExtension, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: AppTypography.body(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FileSizeFormatter.format(fileSizeBytes),
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: onRemove,
              tooltip: 'Remove file',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
