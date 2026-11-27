import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/timetable.dart';

/// A rectangular selection of boxes (inclusive), always normalised so that
/// the first corner is top-left.
class CellRange {
  final int r1;
  final int c1;
  final int r2;
  final int c2;

  const CellRange(this.r1, this.c1, this.r2, this.c2);

  factory CellRange.between(int ar, int ac, int fr, int fc) => CellRange(
        ar < fr ? ar : fr,
        ac < fc ? ac : fc,
        ar < fr ? fr : ar,
        ac < fc ? fc : ac,
      );

  bool contains(int r, int c) => r >= r1 && r <= r2 && c >= c1 && c <= c2;
  int get rowCount => r2 - r1 + 1;
  int get colCount => c2 - c1 + 1;
  bool get isSingle => r1 == r2 && c1 == c2;
}

/// "A", "B", ... "T": spreadsheet-style column letter.
String columnLabel(int col) => String.fromCharCode(65 + col);

/// "A1" or "A1:C3".
String rangeLabel(CellRange range) {
  final first = '${columnLabel(range.c1)}${range.r1 + 1}';
  if (range.isSingle) return first;
  return '$first:${columnLabel(range.c2)}${range.r2 + 1}';
}

/// The grid itself. Read-only in the viewer; in the editor it adds
/// spreadsheet-style column letters and row numbers, shows the selection
/// and reports taps. Scrolls in both directions, so it works on a phone,
/// a tablet and a desktop window alike.
///
/// Boxes always render on a "paper" look (explicit colours), so a
/// timetable looks the same in the app's light and dark themes and prints
/// the way it was designed.
class TimetableGrid extends StatelessWidget {
  static const double rowHeaderWidth = 40;
  static const double colHeaderHeight = 28;

  final Timetable timetable;
  final bool editable;
  final CellRange? selection;
  final void Function(int row, int col)? onCellTap;
  final void Function(int row, int col)? onCellDoubleTap;
  final void Function(int row)? onRowHeaderTap;
  final void Function(int col)? onColHeaderTap;

  const TimetableGrid({
    super.key,
    required this.timetable,
    this.editable = false,
    this.selection,
    this.onCellTap,
    this.onCellDoubleTap,
    this.onRowHeaderTap,
    this.onColHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (editable) _columnHeaders(),
              for (var r = 0; r < timetable.rows; r++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (editable) _rowHeader(r),
                      for (var c = 0; c < timetable.cols; c++) _box(r, c),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBox({
    required String text,
    required double width,
    required double height,
    required bool highlighted,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted ? const Color(0xFFCFE0E6) : const Color(0xFFEDEDED),
          border: Border.all(color: Colors.black26, width: 0.5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _columnHeaders() {
    return Row(
      children: [
        SizedBox(width: rowHeaderWidth, height: colHeaderHeight),
        for (var c = 0; c < timetable.cols; c++)
          _headerBox(
            text: columnLabel(c),
            width: timetable.colWidths[c].toDouble(),
            height: colHeaderHeight,
            highlighted:
                selection != null && c >= selection!.c1 && c <= selection!.c2,
            onTap: onColHeaderTap == null ? null : () => onColHeaderTap!(c),
          ),
      ],
    );
  }

  Widget _rowHeader(int r) {
    return _headerBox(
      text: '${r + 1}',
      width: rowHeaderWidth,
      height: 44,
      highlighted:
          selection != null && r >= selection!.r1 && r <= selection!.r2,
      onTap: onRowHeaderTap == null ? null : () => onRowHeaderTap!(r),
    );
  }

  Widget _box(int r, int c) {
    final cell = timetable.cell(r, c);
    final bgColor = cell.bg == null ? Colors.white : Color(cell.bg!);
    final fgColor = cell.fg != null
        ? Color(cell.fg!)
        : (ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark
            ? Colors.white
            : Colors.black87);
    final selected = selection?.contains(r, c) ?? false;

    final alignment = cell.align == 1
        ? Alignment.center
        : cell.align == 2
            ? Alignment.centerRight
            : Alignment.centerLeft;
    final textAlign = cell.align == 1
        ? TextAlign.center
        : cell.align == 2
            ? TextAlign.right
            : TextAlign.left;
    final fontSize = cell.size == 0 ? 11.0 : (cell.size == 2 ? 17.0 : 13.5);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCellTap == null ? null : () => onCellTap!(r, c),
      onDoubleTap:
          onCellDoubleTap == null ? null : () => onCellDoubleTap!(r, c),
      child: Container(
        width: timetable.colWidths[c].toDouble(),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        alignment: alignment,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: Colors.black26, width: 0.5),
        ),
        foregroundDecoration: selected
            ? BoxDecoration(
                color: AppColors.primary.withAlpha(35),
                border: Border.all(color: AppColors.primary, width: 2),
              )
            : null,
        child: Text(
          cell.text,
          textAlign: textAlign,
          style: TextStyle(
            color: fgColor,
            fontSize: fontSize,
            fontWeight: cell.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: cell.italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}
