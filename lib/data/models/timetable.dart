import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// What a timetable is for. [value] is the stored Firestore string and must
/// match the type list in the `timetables` rules.
enum TimetableType {
  classTimetable('class', 'Class timetable', Icons.schedule),
  exam('exam', 'Exam timetable', Icons.assignment),
  calendar('calendar', 'School calendar', Icons.calendar_month),
  semesterCalendar('semester_calendar', 'Semester calendar', Icons.date_range),
  custom('custom', 'Other', Icons.grid_on);

  final String value;
  final String label;
  final IconData icon;
  const TimetableType(this.value, this.label, this.icon);

  static TimetableType fromValue(String? value) => TimetableType.values
      .firstWhere((t) => t.value == value, orElse: () => TimetableType.custom);
}

/// Who the timetable is listed for. This only decides where it is LISTED
/// in the app. Any published timetable can be read by anyone holding the
/// app's public key (students have no sign-in until Phase 5).
enum TimetableAudience {
  everyone('everyone', 'Everyone (public)'),
  students('students', 'Students'),
  staff('staff', 'Staff and tutors');

  final String value;
  final String label;
  const TimetableAudience(this.value, this.label);

  static TimetableAudience fromValue(String? value) =>
      TimetableAudience.values.firstWhere(
        (a) => a.value == value,
        orElse: () => TimetableAudience.staff,
      );
}

enum TimetableStatus { draft, published }

/// One box of the grid. Colours are stored as ARGB ints; null means
/// "default". Short keys keep the Firestore document small.
class TimetableCell {
  final String text;
  final int? bg;
  final int? fg;
  final bool bold;
  final bool italic;

  /// 0 left, 1 centre, 2 right.
  final int align;

  /// 0 small, 1 normal, 2 large.
  final int size;

  const TimetableCell({
    this.text = '',
    this.bg,
    this.fg,
    this.bold = false,
    this.italic = false,
    this.align = 0,
    this.size = 1,
  });

  bool get isEmpty =>
      text.isEmpty &&
      bg == null &&
      fg == null &&
      !bold &&
      !italic &&
      align == 0 &&
      size == 1;

  TimetableCell copyWith({
    String? text,
    int? bg,
    int? fg,
    bool clearBg = false,
    bool clearFg = false,
    bool? bold,
    bool? italic,
    int? align,
    int? size,
  }) {
    return TimetableCell(
      text: text ?? this.text,
      bg: clearBg ? null : (bg ?? this.bg),
      fg: clearFg ? null : (fg ?? this.fg),
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      align: align ?? this.align,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toMap() => {
        if (text.isNotEmpty) 't': text,
        if (bg != null) 'b': bg,
        if (fg != null) 'f': fg,
        if (bold) 'B': true,
        if (italic) 'I': true,
        if (align != 0) 'a': align,
        if (size != 1) 's': size,
      };

  factory TimetableCell.fromMap(Map<String, dynamic> map) => TimetableCell(
        text: (map['t'] as String?) ?? '',
        bg: (map['b'] as num?)?.toInt(),
        fg: (map['f'] as num?)?.toInt(),
        bold: (map['B'] as bool?) ?? false,
        italic: (map['I'] as bool?) ?? false,
        align: ((map['a'] as num?)?.toInt() ?? 0).clamp(0, 2),
        size: ((map['s'] as num?)?.toInt() ?? 1).clamp(0, 2),
      );
}

/// A spreadsheet-style timetable or calendar: a grid of [TimetableCell]s
/// plus a title, subtitle and footnotes. The whole grid lives in ONE
/// document so a screen is a single read and a save is a single write
/// (a 60 x 20 grid is a few tens of KB, well under the 1 MiB limit).
///
/// Immutable; the editing helpers return a new [Timetable].
class Timetable {
  static const int maxRows = 60;
  static const int maxCols = 20;
  static const int minColWidth = 60;
  static const int maxColWidth = 320;
  static const int defaultColWidth = 120;
  static const int maxFootnotes = 12;

  final String id;
  final String title;
  final String subtitle;
  final String academicYear;

  /// ProgramType name, or '' for "all programs".
  final String programType;

  /// 0 means "all years" / "all semesters".
  final int year;
  final int semester;

  final TimetableType type;
  final TimetableAudience audience;
  final TimetableStatus status;
  final int rows;
  final int cols;
  final List<int> colWidths;

  /// Keyed "r{row}c{col}", zero-based. Missing key = plain empty box.
  final Map<String, TimetableCell> cells;
  final List<String> footnotes;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  const Timetable({
    this.id = '',
    required this.title,
    this.subtitle = '',
    this.academicYear = '',
    this.programType = '',
    this.year = 0,
    this.semester = 0,
    required this.type,
    this.audience = TimetableAudience.staff,
    this.status = TimetableStatus.draft,
    required this.rows,
    required this.cols,
    required this.colWidths,
    required this.cells,
    this.footnotes = const [],
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  });

  static final RegExp _keyPattern = RegExp(r'^r(\d+)c(\d+)$');
  static String key(int row, int col) => 'r${row}c$col';

  bool get isPublished => status == TimetableStatus.published;

  TimetableCell cell(int row, int col) =>
      cells[key(row, col)] ?? const TimetableCell();

  Timetable copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? academicYear,
    String? programType,
    int? year,
    int? semester,
    TimetableType? type,
    TimetableAudience? audience,
    TimetableStatus? status,
    int? rows,
    int? cols,
    List<int>? colWidths,
    Map<String, TimetableCell>? cells,
    List<String>? footnotes,
  }) {
    return Timetable(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      academicYear: academicYear ?? this.academicYear,
      programType: programType ?? this.programType,
      year: year ?? this.year,
      semester: semester ?? this.semester,
      type: type ?? this.type,
      audience: audience ?? this.audience,
      status: status ?? this.status,
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
      colWidths: colWidths ?? this.colWidths,
      cells: cells ?? this.cells,
      footnotes: footnotes ?? this.footnotes,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      publishedAt: publishedAt,
    );
  }

  // ---- grid editing helpers (each returns a new Timetable) -------------

  Timetable withCell(int row, int col, TimetableCell cell) {
    final next = Map<String, TimetableCell>.from(cells);
    if (cell.isEmpty) {
      next.remove(key(row, col));
    } else {
      next[key(row, col)] = cell;
    }
    return copyWith(cells: next);
  }

  Timetable insertRow(int at) {
    if (rows >= maxRows) return this;
    final next = <String, TimetableCell>{};
    cells.forEach((k, v) {
      final m = _keyPattern.firstMatch(k);
      if (m == null) return;
      final r = int.parse(m.group(1)!);
      final c = int.parse(m.group(2)!);
      next[key(r >= at ? r + 1 : r, c)] = v;
    });
    return copyWith(rows: rows + 1, cells: next);
  }

  Timetable deleteRow(int at) {
    if (rows <= 1 || at < 0 || at >= rows) return this;
    final next = <String, TimetableCell>{};
    cells.forEach((k, v) {
      final m = _keyPattern.firstMatch(k);
      if (m == null) return;
      final r = int.parse(m.group(1)!);
      final c = int.parse(m.group(2)!);
      if (r == at) return;
      next[key(r > at ? r - 1 : r, c)] = v;
    });
    return copyWith(rows: rows - 1, cells: next);
  }

  Timetable insertCol(int at) {
    if (cols >= maxCols) return this;
    final next = <String, TimetableCell>{};
    cells.forEach((k, v) {
      final m = _keyPattern.firstMatch(k);
      if (m == null) return;
      final r = int.parse(m.group(1)!);
      final c = int.parse(m.group(2)!);
      next[key(r, c >= at ? c + 1 : c)] = v;
    });
    final widths = List<int>.from(colWidths)..insert(at, defaultColWidth);
    return copyWith(cols: cols + 1, cells: next, colWidths: widths);
  }

  Timetable deleteCol(int at) {
    if (cols <= 1 || at < 0 || at >= cols) return this;
    final next = <String, TimetableCell>{};
    cells.forEach((k, v) {
      final m = _keyPattern.firstMatch(k);
      if (m == null) return;
      final r = int.parse(m.group(1)!);
      final c = int.parse(m.group(2)!);
      if (c == at) return;
      next[key(r, c > at ? c - 1 : c)] = v;
    });
    final widths = List<int>.from(colWidths)..removeAt(at);
    return copyWith(cols: cols - 1, cells: next, colWidths: widths);
  }

  Timetable withColWidth(int col, int width) {
    final widths = List<int>.from(colWidths);
    widths[col] = width.clamp(minColWidth, maxColWidth);
    return copyWith(colWidths: widths);
  }

  // ---- Firestore -------------------------------------------------------

  Map<String, dynamic> _cellsMap() =>
      {for (final e in cells.entries) e.key: e.value.toMap()};

  /// Fields for a brand-new document (the repository adds createdBy,
  /// createdAt, updatedAt and updatedBy).
  Map<String, dynamic> toCreateMap() => {
        'title': title,
        'type': type.value,
        'audience': audience.value,
        'status': status.name,
        'rows': rows,
        'cols': cols,
        'colWidths': colWidths,
        'cells': _cellsMap(),
        'footnotes': footnotes,
        if (subtitle.isNotEmpty) 'subtitle': subtitle,
        if (academicYear.isNotEmpty) 'academicYear': academicYear,
        if (programType.isNotEmpty) 'programType': programType,
        if (year > 0) 'year': year,
        if (semester > 0) 'semester': semester,
      };

  /// Content fields for an update. Status is NOT included: it changes only
  /// through publish / unpublish. Optional fields that are now empty are
  /// deleted from the document.
  Map<String, dynamic> toUpdateMap() => {
        'title': title,
        'type': type.value,
        'audience': audience.value,
        'rows': rows,
        'cols': cols,
        'colWidths': colWidths,
        'cells': _cellsMap(),
        'footnotes': footnotes,
        'subtitle':
            subtitle.isNotEmpty ? subtitle : FieldValue.delete(),
        'academicYear':
            academicYear.isNotEmpty ? academicYear : FieldValue.delete(),
        'programType':
            programType.isNotEmpty ? programType : FieldValue.delete(),
        'year': year > 0 ? year : FieldValue.delete(),
        'semester': semester > 0 ? semester : FieldValue.delete(),
      };

  factory Timetable.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rows = ((data['rows'] as num?)?.toInt() ?? 1).clamp(1, maxRows);
    final cols = ((data['cols'] as num?)?.toInt() ?? 1).clamp(1, maxCols);

    // Column widths: pad or trim so the list always matches `cols`.
    final rawWidths = (data['colWidths'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        <int>[];
    final widths = List<int>.generate(
      cols,
      (i) => (i < rawWidths.length ? rawWidths[i] : defaultColWidth)
          .clamp(minColWidth, maxColWidth),
    );

    final cells = <String, TimetableCell>{};
    final rawCells = data['cells'] as Map<String, dynamic>? ?? {};
    rawCells.forEach((k, v) {
      final m = _keyPattern.firstMatch(k);
      if (m == null || v is! Map<String, dynamic>) return;
      final r = int.parse(m.group(1)!);
      final c = int.parse(m.group(2)!);
      if (r < rows && c < cols) cells[k] = TimetableCell.fromMap(v);
    });

    return Timetable(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      subtitle: (data['subtitle'] as String?) ?? '',
      academicYear: (data['academicYear'] as String?) ?? '',
      programType: (data['programType'] as String?) ?? '',
      year: (data['year'] as num?)?.toInt() ?? 0,
      semester: (data['semester'] as num?)?.toInt() ?? 0,
      type: TimetableType.fromValue(data['type'] as String?),
      audience: TimetableAudience.fromValue(data['audience'] as String?),
      status: data['status'] == 'published'
          ? TimetableStatus.published
          : TimetableStatus.draft,
      rows: rows,
      cols: cols,
      colWidths: widths,
      cells: cells,
      footnotes:
          (data['footnotes'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate(),
    );
  }
}
