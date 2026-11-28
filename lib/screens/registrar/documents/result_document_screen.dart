import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/result_pdf.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/utils/student_number.dart';
import '../../../data/models/coursework.dart';
import '../../../data/models/result_document.dart';
import '../../../data/models/student_record.dart';
import '../../../data/models/uhpab.dart';
import '../../../data/repositories/coursework_repository.dart';
import '../../../data/repositories/document_template_repository.dart';
import '../../../data/repositories/uhpab_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';

/// The Registrar prepares a student's result slip or transcript, edits any
/// part of it and saves it as a PDF.
class ResultDocumentScreen extends StatefulWidget {
  final StudentRecord student;
  const ResultDocumentScreen({super.key, required this.student});

  @override
  State<ResultDocumentScreen> createState() => _ResultDocumentScreenState();
}

class _ResultDocumentScreenState extends State<ResultDocumentScreen> {
  final _templates = DocumentTemplateRepository();
  List<CourseworkEntry> _coursework = [];
  List<UhpabUnit> _uhpab = [];
  DocumentTemplate? _template;
  ResultDocument? _document;

  /// The year and semester of a result slip, or null for a transcript.
  (int, int)? _only;

  /// Whether anything has been typed since the document was filled in.
  bool _edited = false;

  /// Counts refills, so that the form fields take the new text.
  int _version = 0;
  AppFailure? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final template = await _templates.load();
      final coursework =
          await CourseworkRepository().forStudent(widget.student.nsin);
      final uhpab =
          (await UhpabRepository().watch(widget.student.nsin).first).units;
      if (!mounted) return;
      _template = template;
      _coursework = coursework;
      _uhpab = uhpab;
      setState(_fill);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is AppFailure
            ? e
            : const CourseworkFailure(
                'Could not load the results. Check your connection and try '
                'again.',
              ),
      );
    }
  }

  void _fill() {
    _document = ResultDocument.build(
      student: widget.student,
      template: _template!,
      coursework: _coursework,
      uhpab: _uhpab,
      issued: DateFormat('d MMMM yyyy').format(DateTime.now()),
      only: _only,
    );
    _edited = false;
    _version++;
  }

  Future<bool> _confirmDiscard() async =>
      !_edited ||
      (await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Discard your edits?'),
              content: const Text(
                'Edits to this document are not kept. Save the PDF first if '
                'you need them.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard'),
                ),
              ],
            ),
          ) ??
          false);

  Future<void> _choose((int, int)? only) async {
    if (!await _confirmDiscard() || !mounted) {
      // Puts the picker back on the document that is still shown.
      if (mounted) setState(() => _version++);
      return;
    }
    setState(() {
      _only = only;
      _fill();
    });
  }

  Future<void> _savePdf() async {
    final kind = _only == null
        ? 'transcript'
        : 'results_Y${_only!.$1}S${_only!.$2}';
    final logo = await rootBundle.load('assets/images/school_logo.jpg');
    if (!mounted) return;
    await saveToPhone(
      context,
      '${kind}_${StudentNumber.bioKey(widget.student.nsin)}.pdf',
      resultPdf(
        _document!,
        logo: logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes),
      ),
    );
  }

  Future<void> _saveTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    final document = _document!;
    final values = {
      ...document.wording,
      _only == null ? 'transcriptTitle' : 'slipTitle': document.title,
    };
    setState(() => _busy = true);
    try {
      await _templates.save(values);
      _template = DocumentTemplate.fromMap(values);
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved as the school template.')),
      );
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A change to the document's text.
  void _change(VoidCallback apply) {
    apply();
    if (!_edited) setState(() => _edited = true);
  }

  Widget _field(
    String label,
    String value,
    void Function(String) onChanged, {
    int? maxLength,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextFormField(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          minLines: 1,
          maxLines: 3,
          maxLength: maxLength,
          onChanged: (text) => _change(() => onChanged(text)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return PopScope(
      canPop: !_edited,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Slip and transcript')),
        body: _error != null
            ? AppErrorDisplay(failure: _error!, onRetry: _load)
            : document == null
                ? const AppLoadingIndicator()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildForm(document),
                  ),
        bottomNavigationBar: document == null || _error != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    onPressed: _savePdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Save PDF'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildForm(ResultDocument document) {
    final classes = ResultDocument.classes(_coursework, _uhpab);
    final headings = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<(int, int)?>(
          key: ValueKey('kind $_version'),
          initialValue: _only,
          decoration: const InputDecoration(labelText: 'Document'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Transcript')),
            for (final c in classes)
              DropdownMenuItem(
                value: c,
                child: Text('Result slip: Year ${c.$1}, Semester ${c.$2}'),
              ),
          ],
          onChanged: _choose,
        ),
        const SizedBox(height: 8),
        const Text(
          'Filled from published results. Everything below can be edited; '
          'edits change this PDF only, not the student\'s records. UHPAB '
          'results are held from students with unpaid fees, so check with the '
          'Bursar before handing this over.',
        ),
        Column(
          key: ValueKey(_version),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('School heading, signatures and note'),
              // Keeps typed text while closed.
              maintainState: true,
              children: [
                for (final entry in DocumentTemplate.labels.entries)
                  if (!entry.key.endsWith('Title'))
                    _field(
                      entry.value,
                      document.wording[entry.key] ?? '',
                      (v) => document.wording[entry.key] = v,
                      maxLength: DocumentTemplate.maxLength,
                    ),
              ],
            ),
            _field(
              'Title',
              document.title,
              (v) => document.title = v,
              maxLength: DocumentTemplate.maxLength,
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _saveTemplate,
              icon: const Icon(Icons.save),
              label: const Text('Save heading and title as the template'),
            ),
            const SizedBox(height: 16),
            Text('Student details', style: headings),
            for (final detail in document.details)
              _field(detail.label, detail.value, (v) => detail.value = v),
            if (document.sections.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('No published results yet.'),
              ),
            for (final section in document.sections)
              _buildSection(section, headings),
            TextButton.icon(
              onPressed: () => _change(
                () => setState(
                  () => document.sections.add(
                    ResultSection(heading: 'New section', rows: [ResultRow()]),
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add a section'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection(ResultSection section, TextStyle? headings) {
    return Column(
      key: ObjectKey(section),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        _field('Heading', section.heading, (v) => section.heading = v),
        for (final row in section.rows) _buildRow(section, row),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _edited = true;
              section.rows.add(ResultRow());
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add a course unit'),
        ),
        _field(
          'Summary line (for example the GPA)',
          section.summary,
          (v) => section.summary = v,
        ),
      ],
    );
  }

  Widget _buildRow(ResultSection section, ResultRow row) {
    Widget cell(String label, String value, void Function(String) onChanged) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _field(label, value, onChanged),
          ),
        );
    return Card(
      key: ObjectKey(row),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _field(
                    'Course unit',
                    row.unit,
                    (v) => row.unit = v,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove from this document',
                  onPressed: () => setState(() {
                    _edited = true;
                    section.rows.remove(row);
                  }),
                ),
              ],
            ),
            Row(
              children: [
                cell('/40', row.coursework, (v) => row.coursework = v),
                cell('UHPAB', row.uhpab, (v) => row.uhpab = v),
                cell('Grade', row.grade, (v) => row.grade = v),
                cell('Points', row.points, (v) => row.points = v),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
