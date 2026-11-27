import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/upload_rules.dart';
import '../../core/errors/app_failure.dart';
import '../../data/models/public_post.dart';
import '../../data/repositories/public_post_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_error_display.dart';
import 'public_post_widgets.dart';

/// Create a public post. Open to signed-in staff (Principal, Registrar,
/// Bursar) and tutors. Staff posts go live at once; a tutor's post is
/// submitted for the Principal or Registrar to approve.
///
/// Pictures and documents are uploaded, with the same types and size limit as
/// tutor uploads. Video and audio are added as a link.
class PublicComposeScreen extends StatefulWidget {
  const PublicComposeScreen({super.key});

  @override
  State<PublicComposeScreen> createState() => _PublicComposeScreenState();
}

class _PublicComposeScreenState extends State<PublicComposeScreen> {
  final _repository = PublicPostRepository();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _mediaController = TextEditingController();
  static const _maxFiles = 10;
  final List<PostFile> _files = [];
  int _uploading = 0; // which file is being sent
  String? _fileError;

  PublicCategory _category = PublicCategory.announcement;
  DateTime? _eventDate;
  bool _submitting = false;
  AppFailure? _error;
  String? _dateError;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _mediaController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() {
        _eventDate = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: UploadRules.allowedExtensions,
    );
    if (result == null || !mounted) return;

    String? problem;
    final added = <PostFile>[];
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null ||
          !UploadRules.isExtensionAllowed(picked.extension ?? '')) {
        problem = '${picked.name} cannot be uploaded.';
      } else if (picked.size == 0 ||
          !UploadRules.isWithinSizeLimit(picked.size)) {
        problem = '${picked.name} is empty or larger than '
            '${UploadRules.maxFileSizeLabel}.';
      } else if (_files.length + added.length >= _maxFiles) {
        problem = 'A post can have at most $_maxFiles files.';
      } else {
        added.add((name: picked.name, file: File(path)));
      }
    }
    setState(() {
      _files.addAll(added);
      _fileError = problem;
    });
  }

  Future<void> _submit(AuthProvider auth) async {
    final valid = _formKey.currentState!.validate();
    if (_category == PublicCategory.event && _eventDate == null) {
      setState(() => _dateError = 'Pick the date of the event');
      return;
    }
    if (_category == PublicCategory.gallery &&
        !_files.any((f) => PublicPost.isPicture(f.name))) {
      setState(() => _fileError = 'Gallery posts need a JPG or PNG picture');
      return;
    }
    if (!valid) return;

    // Who is posting, and under what name/role. These must match the
    // account records, or the rules reject the post.
    final staff = auth.staffAccount;
    final tutor = auth.tutorAccount;
    final String authorName;
    final String authorRole;
    final bool publishDirectly;
    if (staff != null && staff.isActive) {
      authorName = staff.name;
      authorRole = staff.role.name;
      publishDirectly = true;
    } else if (tutor != null && tutor.isActive) {
      authorName = tutor.name;
      authorRole = 'tutor';
      publishDirectly = false;
    } else {
      setState(() => _error = const UnauthorizedActionFailure(
            'Please sign in to post.',
          ));
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repository.create(
        category: _category,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        authorName: authorName,
        authorRole: authorRole,
        publishDirectly: publishDirectly,
        eventDate: _category == PublicCategory.event ? _eventDate : null,
        mediaUrl: _mediaController.text.trim(),
        files: List.of(_files),
        onUploading: (number) {
          if (mounted) setState(() => _uploading = number);
        },
      );
      messenger.showSnackBar(SnackBar(
        content: Text(publishDirectly
            ? 'Posted to the public space.'
            : 'Submitted. It will appear once the Principal or Registrar '
                'approves it.'),
      ));
      if (mounted) context.pop(true);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploading = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isTutor = !(auth.staffAccount?.isActive ?? false);

    return Scaffold(
      appBar: AppBar(title: const Text('New public post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isTutor
                      ? 'This will be visible to anyone who downloads the app, '
                          'after the Principal or Registrar approves it. '
                          'Do not include private information.'
                      : 'This will be visible to anyone who downloads the '
                          'app. Do not include private information.',
                ),
              ),
              const SizedBox(height: 20),
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in PublicCategory.values)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 18),
                      label: Text(c.label),
                      selected: _category == c,
                      onSelected: _submitting
                          ? null
                          : (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Enter a title (at least 3 characters)'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyController,
                minLines: 4,
                maxLines: 10,
                maxLength: 5000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter some details'
                    : null,
              ),
              if (_category == PublicCategory.event) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text(_eventDate == null
                      ? 'Pick the event date'
                      : 'Event date: ${formatPostDate(_eventDate)}'),
                ),
                if (_dateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(
                      _dateError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickFiles,
                icon: const Icon(Icons.attach_file),
                label: const Text('Add pictures or documents'),
              ),
              for (final f in _files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PublicPost.isPicture(f.name)
                      ? Image.file(f.file,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          cacheWidth: 144)
                      : const Icon(Icons.description),
                  title: Text(f.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove',
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _files.remove(f)),
                  ),
                ),
              if (_fileError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                    _fileError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mediaController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Video or audio link (optional)',
                  helperText: 'A link starting with https://',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null;
                  if (!value.startsWith('https://') || value.length > 500) {
                    return 'Use a link starting with https://';
                  }
                  return null;
                },
              ),
              if (_uploading > 0) ...[
                const SizedBox(height: 16),
                Text('Uploading file $_uploading of ${_files.length}…'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                AppInlineError(failure: _error!),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitting ? null : () => _submit(auth),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isTutor ? 'Submit for approval' : 'Publish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
