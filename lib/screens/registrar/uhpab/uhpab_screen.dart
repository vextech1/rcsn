import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/upload_rules.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/subject.dart';
import '../../../data/models/uhpab.dart';
import '../../../data/repositories/structure_repository.dart';
import '../../../data/repositories/uhpab_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import '../../../widgets/coursework/open_result_document.dart';

/// One student's UHPAB results: typed marks and uploaded documents. The
/// Registrar edits them; the Principal and Deputy only look.
class UhpabScreen extends StatefulWidget {
  final StudentRecord student;
  const UhpabScreen({super.key, required this.student});

  @override
  State<UhpabScreen> createState() => _UhpabScreenState();
}

class _UhpabScreenState extends State<UhpabScreen> {
  final _repository = UhpabRepository();
  late final _results = _repository.watch(_nsin);
  late final bool _canEdit =
      context.read<AuthProvider>().resolvedRole == UserRole.registrar;
  bool _busy = false;

  String get _nsin => widget.student.nsin;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      _say(done);
    } on AppFailure catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editUnit(List<UhpabUnit> recorded, [UhpabUnit? unit]) async {
    var subjects = <Subject>[];
    if (unit == null) {
      setState(() => _busy = true);
      try {
        final all = await StructureRepository()
            .watchSubjectsForTrack(widget.student.programType)
            .first;
        final taken = {for (final u in recorded) u.subjectId};
        subjects = [
          for (final s in all)
            if (!taken.contains(s.id)) s,
        ];
      } catch (_) {
        _say('Could not load the course units.');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (subjects.isEmpty) {
        _say('There are no more course units to add.');
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<UhpabUnit>(
      context: context,
      builder: (_) => _MarkDialog(unit: unit, subjects: subjects),
    );
    if (saved == null || !mounted) return;
    await _run(
      () => _repository.saveUnit(_nsin, saved),
      saved.published ? 'Published.' : 'Saved as a draft.',
    );
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: UploadRules.allowedExtensions,
    );
    final file = picked?.files.single;
    final path = file?.path;
    if (file == null || path == null || !mounted) return;
    if (!UploadRules.isExtensionAllowed(file.extension ?? '') ||
        file.size == 0 ||
        !UploadRules.isWithinSizeLimit(file.size)) {
      _say(
        'Choose a picture or document of at most '
        '${UploadRules.maxFileSizeLabel}.',
      );
      return;
    }
    await _run(
      () => _repository.addDocument(_nsin, File(path), file.name),
      'Uploaded as a draft. Publish it for the student to see it.',
    );
  }

  Future<void> _unitAction(
    String action,
    UhpabUnit unit,
    List<UhpabUnit> all,
  ) async {
    switch (action) {
      case 'edit':
        await _editUnit(all, unit);
      case 'publish':
        await _run(
          () => _repository.saveUnit(_nsin, unit.withPublished(true)),
          'Published.',
        );
      case 'recall':
        await _run(
          () => _repository.saveUnit(_nsin, unit.withPublished(false)),
          'Recalled. The student no longer sees it.',
        );
      case 'delete':
        if (await _confirm('Delete this mark?', unit.subjectName, 'Delete') &&
            mounted) {
          await _run(
            () => _repository.deleteUnit(_nsin, unit.subjectId),
            'Deleted.',
          );
        }
    }
  }

  Future<void> _documentAction(String action, UhpabDocument document) async {
    switch (action) {
      case 'publish':
        await _run(
          () => _repository.saveDocument(_nsin, document.withPublished(true)),
          'Published.',
        );
      case 'recall':
        await _run(
          () => _repository.saveDocument(_nsin, document.withPublished(false)),
          'Recalled. The student no longer sees it.',
        );
      case 'delete':
        if (await _confirm('Delete this file?', document.title, 'Delete') &&
            mounted) {
          await _run(
            () => _repository.deleteDocument(_nsin, document),
            'Deleted.',
          );
        }
    }
  }

  Future<void> _postPublicly() async {
    final go = await _confirm(
      'Post results publicly?',
      'Everyone will see a public post, without signing in. A class sheet '
          'shows all results, including those of students with unpaid fees.',
      'Continue',
    );
    if (go && mounted) await context.push(AppRoutes.publicNew);
  }

  List<PopupMenuEntry<String>> _menu(bool published, {bool canEdit = false}) =>
      [
        if (canEdit)
          const PopupMenuItem(value: 'edit', child: Text('Change mark')),
        published
            ? const PopupMenuItem(value: 'recall', child: Text('Recall'))
            : const PopupMenuItem(value: 'publish', child: Text('Publish')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ];

  @override
  Widget build(BuildContext context) {
    final headings = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('UHPAB results')),
      body: StreamBuilder<UhpabResults>(
        stream: _results,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const AppErrorDisplay(
              failure: CourseworkFailure(
                'Could not load the results. Check your connection and '
                'permissions.',
              ),
            );
          }
          final results = snapshot.data;
          if (results == null) return const AppLoadingIndicator();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.student.name} · $_nsin',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Unpaid fees hide published results from the student until '
                'the Bursar allows viewing.',
              ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text('Marks', style: headings),
              if (results.units.isEmpty) const Text('No marks typed.'),
              for (final unit in results.units)
                Card(
                  child: ListTile(
                    title: Text(unit.subjectName),
                    subtitle: Text(
                      'Year ${unit.year}, Semester ${unit.semester}\n'
                      '${unit.summary} · '
                      '${unit.published ? 'Published' : 'Draft'}',
                    ),
                    isThreeLine: true,
                    trailing: _canEdit
                        ? PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (a) =>
                                _unitAction(a, unit, results.units),
                            itemBuilder: (_) =>
                                _menu(unit.published, canEdit: true),
                          )
                        : null,
                  ),
                ),
              if (_canEdit)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _editUnit(results.units),
                  icon: const Icon(Icons.add),
                  label: const Text('Type a mark'),
                ),
              const SizedBox(height: 24),
              Text('Documents', style: headings),
              if (results.documents.isEmpty) const Text('No documents.'),
              for (final document in results.documents)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(document.title),
                    subtitle: Text(document.published ? 'Published' : 'Draft'),
                    onTap: () => openResultDocument(context, _nsin, document),
                    trailing: _canEdit
                        ? PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (a) => _documentAction(a, document),
                            itemBuilder: (_) => _menu(document.published),
                          )
                        : null,
                  ),
                ),
              if (_canEdit) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload a document'),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: _busy ? null : _postPublicly,
                  icon: const Icon(Icons.campaign),
                  label: const Text('Post results publicly'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Types or changes one mark. Returns it as a draft or to be published.
class _MarkDialog extends StatefulWidget {
  /// The mark being changed, or null to add one for one of [subjects].
  final UhpabUnit? unit;
  final List<Subject> subjects;

  const _MarkDialog({required this.unit, required this.subjects});

  @override
  State<_MarkDialog> createState() => _MarkDialogState();
}

class _MarkDialogState extends State<_MarkDialog> {
  final _form = GlobalKey<FormState>();
  late final _mark = TextEditingController(text: widget.unit?.markLabel);
  Subject? _subject;

  @override
  void dispose() {
    _mark.dispose();
    super.dispose();
  }

  void _finish({required bool publish}) {
    if (!_form.currentState!.validate()) return;
    final unit = widget.unit;
    final subject = _subject;
    Navigator.pop(
      context,
      UhpabUnit(
        subjectId: unit?.subjectId ?? subject!.id,
        subjectName: unit?.subjectName ?? subject!.name,
        year: unit?.year ?? subject!.year,
        semester: unit?.semester ?? subject!.semester,
        mark: double.parse(_mark.text.trim()),
        published: publish,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final subjects = [...widget.subjects]..sort((a, b) {
        if (a.year != b.year) return a.year - b.year;
        if (a.semester != b.semester) return a.semester - b.semester;
        return a.name.compareTo(b.name);
      });
    return AlertDialog(
      title: Text(unit?.subjectName ?? 'Type a mark'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unit == null)
              DropdownButtonFormField<Subject>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Course unit'),
                items: [
                  for (final s in subjects)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        'Y${s.year} S${s.semester} · ${s.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (s) => _subject = s,
                validator: (s) => s == null ? 'Choose a course unit' : null,
              ),
            TextFormField(
              controller: _mark,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Mark out of 100'),
              validator: (v) => UhpabUnit.markError(v ?? ''),
            ),
            if (unit?.published ?? false)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Saving as a draft hides this result from the student.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _finish(publish: false),
          child: const Text('Save draft'),
        ),
        TextButton(
          onPressed: () => _finish(publish: true),
          child: const Text('Publish'),
        ),
      ],
    );
  }
}
