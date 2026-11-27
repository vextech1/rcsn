import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/academic_structure.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/timetable.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../widgets/common/app_error_display.dart';
import '../../../widgets/common/app_loading_indicator.dart';
import 'timetable_grid.dart';

/// The Registrar's spreadsheet-style editor. Registrar only (the router
/// sends anyone else to the read-only viewer, and the rules enforce it).
///
/// Works with touch, mouse and keyboard: tap a box to select it, tap
/// again (or double-click) to type, use "Range" or Shift+arrows to select
/// several boxes, and the toolbar for colours, text style, rows and
/// columns. Ctrl+Z / Ctrl+Y undo and redo, Ctrl+S saves.
class TimetableEditorScreen extends StatefulWidget {
  final String timetableId;

  const TimetableEditorScreen({super.key, required this.timetableId});

  @override
  State<TimetableEditorScreen> createState() => _TimetableEditorScreenState();
}

class _TimetableEditorScreenState extends State<TimetableEditorScreen> {
  static const int _undoLimit = 50;

  // A readable palette: neutrals, then brand and common highlight colours.
  static const List<int> _palette = [
    0xFFFFFFFF, 0xFFF2F2F2, 0xFFD9D9D9, 0xFF808080, 0xFF000000,
    0xFFFFF3CD, 0xFFFFE082, 0xFFFFCC80, 0xFFEF9A9A, 0xFFF8BBD0,
    0xFFE1BEE7, 0xFFC5CAE9, 0xFFBBDEFB, 0xFFB2EBF2, 0xFFC8E6C9,
    0xFFDCEDC8, 0xFF1F4E5F, 0xFF3A5F3A, 0xFFA67C2E, 0xFFB3261E,
  ];

  final _repository = TimetableRepository();
  final FocusNode _focus = FocusNode();

  Timetable? _tt;
  AppFailure? _loadError;
  bool _dirty = false;
  bool _saving = false;
  bool _rangeMode = false;

  final List<Timetable> _undo = [];
  final List<Timetable> _redo = [];

  // Selection: anchor (where it started) and focus (the moving corner).
  int _anchorR = 0;
  int _anchorC = 0;
  int _focusR = 0;
  int _focusC = 0;

  CellRange get _range =>
      CellRange.between(_anchorR, _anchorC, _focusR, _focusC);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _tt = null;
    });
    try {
      final tt = await _repository.get(widget.timetableId);
      if (!mounted) return;
      if (tt == null) {
        setState(() =>
            _loadError = const UnknownFailure('This timetable no longer exists.'));
      } else {
        setState(() => _tt = tt);
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = UnknownFailure(e.toString()));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- change tracking ----------------------------------------------

  void _apply(Timetable next) {
    final current = _tt;
    if (current == null) return;
    setState(() {
      _undo.add(current);
      if (_undo.length > _undoLimit) _undo.removeAt(0);
      _redo.clear();
      _tt = next;
      _dirty = true;
      _clampSelection();
    });
  }

  void _undoAction() {
    if (_undo.isEmpty || _tt == null) return;
    setState(() {
      _redo.add(_tt!);
      _tt = _undo.removeLast();
      _dirty = true;
      _clampSelection();
    });
  }

  void _redoAction() {
    if (_redo.isEmpty || _tt == null) return;
    setState(() {
      _undo.add(_tt!);
      _tt = _redo.removeLast();
      _dirty = true;
      _clampSelection();
    });
  }

  void _clampSelection() {
    final tt = _tt;
    if (tt == null) return;
    _anchorR = _anchorR.clamp(0, tt.rows - 1);
    _focusR = _focusR.clamp(0, tt.rows - 1);
    _anchorC = _anchorC.clamp(0, tt.cols - 1);
    _focusC = _focusC.clamp(0, tt.cols - 1);
  }

  // ---- selection ----------------------------------------------------

  void _onCellTap(int r, int c) {
    final wasRangeMode = _rangeMode;
    final alreadySelected = _range.isSingle && _anchorR == r && _anchorC == c;
    setState(() {
      if (_rangeMode) {
        _focusR = r;
        _focusC = c;
        _rangeMode = false;
      } else {
        _anchorR = r;
        _anchorC = c;
        _focusR = r;
        _focusC = c;
      }
    });
    _focus.requestFocus();
    // A second tap on the selected box starts typing.
    if (alreadySelected && !wasRangeMode) _editText();
  }

  void _selectRow(int r) {
    setState(() {
      _anchorR = r;
      _focusR = r;
      _anchorC = 0;
      _focusC = _tt!.cols - 1;
    });
    _focus.requestFocus();
  }

  void _selectCol(int c) {
    setState(() {
      _anchorC = c;
      _focusC = c;
      _anchorR = 0;
      _focusR = _tt!.rows - 1;
    });
    _focus.requestFocus();
  }

  void _moveSelection(int dr, int dc, {required bool extend}) {
    final tt = _tt!;
    setState(() {
      _focusR = (_focusR + dr).clamp(0, tt.rows - 1);
      _focusC = (_focusC + dc).clamp(0, tt.cols - 1);
      if (!extend) {
        _anchorR = _focusR;
        _anchorC = _focusC;
      }
    });
  }

  // ---- editing actions ---------------------------------------------

  void _updateSelection(TimetableCell Function(TimetableCell) change) {
    var next = _tt!;
    final range = _range;
    for (var r = range.r1; r <= range.r2; r++) {
      for (var c = range.c1; c <= range.c2; c++) {
        next = next.withCell(r, c, change(next.cell(r, c)));
      }
    }
    _apply(next);
  }

  bool get _allBold {
    final range = _range;
    for (var r = range.r1; r <= range.r2; r++) {
      for (var c = range.c1; c <= range.c2; c++) {
        if (!_tt!.cell(r, c).bold) return false;
      }
    }
    return true;
  }

  bool get _allItalic {
    final range = _range;
    for (var r = range.r1; r <= range.r2; r++) {
      for (var c = range.c1; c <= range.c2; c++) {
        if (!_tt!.cell(r, c).italic) return false;
      }
    }
    return true;
  }

  Future<void> _editText() async {
    final tt = _tt!;
    final range = _range;
    final controller =
        TextEditingController(text: tt.cell(range.r1, range.c1).text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Box ${columnLabel(range.c1)}${range.r1 + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && mounted) {
      final r = range.r1;
      final c = range.c1;
      _apply(_tt!.withCell(r, c, _tt!.cell(r, c).copyWith(text: text)));
    }
    _focus.requestFocus();
  }

  void _clearText() {
    _updateSelection((cell) => cell.copyWith(text: ''));
  }

  Future<void> _pickColor({required bool fill}) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fill ? 'Fill colour' : 'Text colour'),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in _palette)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black38),
                    ),
                  ),
                ),
              ActionChip(
                label: Text(fill ? 'No fill' : 'Automatic'),
                onPressed: () => Navigator.of(ctx).pop(-1),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _updateSelection((cell) {
      if (picked == -1) {
        return fill ? cell.copyWith(clearBg: true) : cell.copyWith(clearFg: true);
      }
      return fill ? cell.copyWith(bg: picked) : cell.copyWith(fg: picked);
    });
    _focus.requestFocus();
  }

  void _cycleSize() {
    final first = _tt!.cell(_range.r1, _range.c1).size;
    final next = (first + 1) % 3;
    _updateSelection((cell) => cell.copyWith(size: next));
  }

  void _insertRow({required bool below}) {
    final tt = _tt!;
    if (tt.rows >= Timetable.maxRows) {
      _snack('A timetable can have up to ${Timetable.maxRows} rows.');
      return;
    }
    final at = below ? _range.r2 + 1 : _range.r1;
    _apply(tt.insertRow(at));
    setState(() {
      _anchorR = at;
      _focusR = at;
    });
  }

  void _insertCol({required bool right}) {
    final tt = _tt!;
    if (tt.cols >= Timetable.maxCols) {
      _snack('A timetable can have up to ${Timetable.maxCols} columns.');
      return;
    }
    final at = right ? _range.c2 + 1 : _range.c1;
    _apply(tt.insertCol(at));
    setState(() {
      _anchorC = at;
      _focusC = at;
    });
  }

  void _deleteRows() {
    var next = _tt!;
    final range = _range;
    if (range.rowCount >= next.rows) {
      _snack('A timetable needs at least one row.');
      return;
    }
    for (var r = range.r2; r >= range.r1; r--) {
      next = next.deleteRow(r);
    }
    _apply(next);
  }

  void _deleteCols() {
    var next = _tt!;
    final range = _range;
    if (range.colCount >= next.cols) {
      _snack('A timetable needs at least one column.');
      return;
    }
    for (var c = range.c2; c >= range.c1; c--) {
      next = next.deleteCol(c);
    }
    _apply(next);
  }

  void _resizeCols(int delta) {
    var next = _tt!;
    final range = _range;
    for (var c = range.c1; c <= range.c2; c++) {
      next = next.withColWidth(c, next.colWidths[c] + delta);
    }
    _apply(next);
  }

  // ---- details and footnotes ----------------------------------------

  Future<void> _editDetails() async {
    final updated = await showDialog<Timetable>(
      context: context,
      builder: (_) => _DetailsDialog(timetable: _tt!),
    );
    if (updated != null && mounted) _apply(updated);
  }

  Future<void> _editFootnotes() async {
    final controller =
        TextEditingController(text: _tt!.footnotes.join('\n'));
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Footnotes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            helperText: 'One footnote per line',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    final notes = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(Timetable.maxFootnotes)
        .toList();
    _apply(_tt!.copyWith(footnotes: notes));
  }

  // ---- save, publish, delete ----------------------------------------

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await _repository.save(_tt!);
      if (mounted) setState(() => _dirty = false);
      _snack('Saved.');
      return true;
    } on AppFailure catch (e) {
      _snack(e.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePublish() async {
    final tt = _tt!;
    if (_dirty && !await _save()) return;
    final target =
        tt.isPublished ? TimetableStatus.draft : TimetableStatus.published;
    try {
      await _repository.setStatus(tt.id, target);
      if (!mounted) return;
      setState(() => _tt = _tt!.copyWith(status: target));
      _snack(target == TimetableStatus.published
          ? 'Published. It is now visible to its audience.'
          : 'Unpublished. It is a draft again.');
    } on AppFailure catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this timetable?'),
        content: const Text('This cannot be undone.'),
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
    try {
      await _repository.delete(_tt!.id);
      if (!mounted) return;
      setState(() => _dirty = false);
      context.pop();
    } on AppFailure catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your changes before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      if (await _save() && mounted) context.pop();
    } else if (choice == 'discard') {
      setState(() => _dirty = false);
      context.pop();
    }
  }

  // ---- keyboard (desktop and web) ------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_tt == null) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;

    if (ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? _redoAction() : _undoAction();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redoAction();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        _save();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyB) {
        final on = !_allBold;
        _updateSelection((c) => c.copyWith(bold: on));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI) {
        final on = !_allItalic;
        _updateSelection((c) => c.copyWith(italic: on));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, 0, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, 0, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(0, -1, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(0, 1, extend: shift);
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _clearText();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.f2) {
      _editText();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- build ---------------------------------------------------------

  Widget _tool(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool active = false,
  }) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      color: active ? AppColors.primary : null,
      style: active
          ? IconButton.styleFrom(
              backgroundColor: AppColors.primary.withAlpha(30),
            )
          : null,
    );
  }

  Widget _divider() => const SizedBox(
        height: 28,
        child: VerticalDivider(width: 12),
      );

  Widget _toolbar(Timetable tt) {
    final first = tt.cell(_range.r1, _range.c1);
    return Material(
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _tool(Icons.edit, 'Edit text', _editText),
            _tool(Icons.format_color_fill, 'Fill colour',
                () => _pickColor(fill: true)),
            _tool(Icons.format_color_text, 'Text colour',
                () => _pickColor(fill: false)),
            _tool(Icons.format_bold, 'Bold (Ctrl+B)', () {
              final on = !_allBold;
              _updateSelection((c) => c.copyWith(bold: on));
            }, active: _allBold),
            _tool(Icons.format_italic, 'Italic (Ctrl+I)', () {
              final on = !_allItalic;
              _updateSelection((c) => c.copyWith(italic: on));
            }, active: _allItalic),
            _tool(Icons.format_size, 'Text size', _cycleSize),
            _tool(Icons.format_align_left, 'Align left',
                () => _updateSelection((c) => c.copyWith(align: 0)),
                active: first.align == 0),
            _tool(Icons.format_align_center, 'Align centre',
                () => _updateSelection((c) => c.copyWith(align: 1)),
                active: first.align == 1),
            _tool(Icons.format_align_right, 'Align right',
                () => _updateSelection((c) => c.copyWith(align: 2)),
                active: first.align == 2),
            _tool(Icons.format_clear, 'Clear formatting',
                () => _updateSelection((c) => TimetableCell(text: c.text))),
            _divider(),
            _tool(Icons.vertical_align_top, 'Insert row above',
                () => _insertRow(below: false)),
            _tool(Icons.vertical_align_bottom, 'Insert row below',
                () => _insertRow(below: true)),
            _tool(Icons.table_rows_outlined, 'Delete selected rows', _deleteRows),
            _divider(),
            _tool(Icons.keyboard_double_arrow_left, 'Insert column left',
                () => _insertCol(right: false)),
            _tool(Icons.keyboard_double_arrow_right, 'Insert column right',
                () => _insertCol(right: true)),
            _tool(Icons.view_column_outlined, 'Delete selected columns',
                _deleteCols),
            _tool(Icons.unfold_less, 'Narrower column', () => _resizeCols(-20)),
            _tool(Icons.unfold_more, 'Wider column', () => _resizeCols(20)),
            _divider(),
            _tool(Icons.select_all, 'Select a range: tap here, then the far corner',
                () => setState(() => _rangeMode = !_rangeMode),
                active: _rangeMode),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Timetable')),
        body: AppErrorDisplay(failure: _loadError!, onRetry: _load),
      );
    }
    final tt = _tt;
    if (tt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Timetable')),
        body: const AppLoadingIndicator(),
      );
    }

    final range = _range;
    final status = _rangeMode
        ? 'Tap the far corner of the range'
        : '${rangeLabel(range)}'
            '${range.isSingle ? '' : ' · ${range.rowCount} × ${range.colCount}'}';

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(
                  child: Text(tt.title, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(tt.isPublished ? 'Published' : 'Draft'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo (Ctrl+Z)',
                onPressed: _undo.isEmpty ? null : _undoAction,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: 'Redo (Ctrl+Y)',
                onPressed: _redo.isEmpty ? null : _redoAction,
              ),
              _saving
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: Icon(_dirty ? Icons.save : Icons.save_outlined),
                      tooltip: 'Save (Ctrl+S)',
                      onPressed: _dirty ? _save : null,
                    ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'details':
                      _editDetails();
                    case 'footnotes':
                      _editFootnotes();
                    case 'publish':
                      _togglePublish();
                    case 'delete':
                      _delete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('Title, type and audience'),
                  ),
                  const PopupMenuItem(
                    value: 'footnotes',
                    child: Text('Footnotes'),
                  ),
                  PopupMenuItem(
                    value: 'publish',
                    child: Text(tt.isPublished ? 'Unpublish' : 'Publish'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _toolbar(tt),
              Expanded(
                child: TimetableGrid(
                  timetable: tt,
                  editable: true,
                  selection: range,
                  onCellTap: _onCellTap,
                  onCellDoubleTap: (r, c) {
                    setState(() {
                      _anchorR = r;
                      _focusR = r;
                      _anchorC = c;
                      _focusC = c;
                    });
                    _editText();
                  },
                  onRowHeaderTap: _selectRow,
                  onColHeaderTap: _selectCol,
                ),
              ),
              if (tt.footnotes.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Colors.black12,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text(
                    tt.footnotes.join('   ·   '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: AppColors.primary.withAlpha(25),
                child: Text(
                  status,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title, subtitle, academic year, type, audience and the optional
/// program / year / semester the timetable applies to.
class _DetailsDialog extends StatefulWidget {
  final Timetable timetable;

  const _DetailsDialog({required this.timetable});

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _year;
  late TimetableType _type;
  late TimetableAudience _audience;
  late String _programType;
  late int _yearNo;
  late int _semester;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final t = widget.timetable;
    _title = TextEditingController(text: t.title);
    _subtitle = TextEditingController(text: t.subtitle);
    _year = TextEditingController(text: t.academicYear);
    _type = t.type;
    _audience = t.audience;
    _programType = t.programType;
    _yearNo = t.year;
    _semester = t.semester;
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _year.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.length < 3) {
      setState(() => _titleError = 'Enter a title (at least 3 characters)');
      return;
    }
    Navigator.of(context).pop(
      widget.timetable.copyWith(
        title: title,
        subtitle: _subtitle.text.trim(),
        academicYear: _year.text.trim(),
        type: _type,
        audience: _audience,
        programType: _programType,
        year: _yearNo,
        semester: _semester,
      ),
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required void Function(T) onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            onSelected: (_) => setState(() => onSelected(v)),
          ),
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Timetable details'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: _titleError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subtitle,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Subtitle (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _year,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: 'Academic year, e.g. 2026/27',
                  border: OutlineInputBorder(),
                ),
              ),
              _heading('Type'),
              _chips<TimetableType>(
                values: TimetableType.values,
                selected: _type,
                label: (t) => t.label,
                onSelected: (t) => _type = t,
              ),
              _heading('Who is it for?'),
              _chips<TimetableAudience>(
                values: TimetableAudience.values,
                selected: _audience,
                label: (a) => a.label,
                onSelected: (a) => _audience = a,
              ),
              _heading('Program (leave on "All" for the whole school)'),
              _chips<String>(
                values: ['', ...ProgramType.values.map((p) => p.name)],
                selected: _programType,
                label: (name) {
                  if (name.isEmpty) return 'All programs';
                  for (final p in ProgramType.values) {
                    if (p.name == name) return kTrackDefinitions[p]?.label ?? name;
                  }
                  return name;
                },
                onSelected: (name) => _programType = name,
              ),
              _heading('Year'),
              _chips<int>(
                values: const [0, 1, 2, 3],
                selected: _yearNo,
                label: (y) => y == 0 ? 'All' : 'Year $y',
                onSelected: (y) => _yearNo = y,
              ),
              _heading('Semester'),
              _chips<int>(
                values: const [0, 1, 2],
                selected: _semester,
                label: (s) => s == 0 ? 'All' : 'Semester $s',
                onSelected: (s) => _semester = s,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}
