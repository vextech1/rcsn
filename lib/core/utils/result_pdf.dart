import 'dart:convert';
import 'dart:typed_data';
import '../../data/models/result_document.dart';

const _left = 50;
const _bottom = 60;
const _top = 800;

/// Table columns: where each starts and how many characters fit at size 10.
const _columns = [(50, 48), (330, 9), (400, 7), (455, 5), (500, 7)];
const _headings = ['Course unit', 'Course /40', 'UHPAB', 'Grade', 'Points'];

/// [value] in lines of at most [width] characters, broken at spaces where
/// possible.
List<String> wrapText(String value, int width) {
  final lines = <String>[];
  var rest = value.trim();
  while (rest.length > width) {
    final space = rest.lastIndexOf(' ', width);
    final cut = space > 0 ? space : width;
    lines.add(rest.substring(0, cut).trimRight());
    rest = rest.substring(cut).trimLeft();
  }
  if (rest.isNotEmpty) lines.add(rest);
  return lines;
}

/// An A4 result slip or transcript, over as many pages as it needs.
Uint8List resultPdf(ResultDocument document) {
  final pages = <StringBuffer>[StringBuffer()];
  var y = _top;

  void newPage() {
    pages.add(StringBuffer());
    y = _top;
  }

  /// Starts a new page unless [height] points are left on this one.
  void need(int height) {
    if (y - height < _bottom) newPage();
  }

  void put(String value, int x, int size, bool bold) {
    pages.last.writeln('BT /${bold ? 'F2' : 'F1'} $size Tf $x $y Td '
        '(${_pdfText(value)}) Tj ET');
  }

  void rule() {
    pages.last.writeln('0.5 w $_left ${y + 4} m 545 ${y + 4} l S');
  }

  void text(String value, {int size = 10, bool bold = false}) {
    // Helvetica averages a little over half its size per character.
    for (final line in wrapText(value, 900 ~/ size)) {
      need(size + 5);
      put(line, _left, size, bold);
      y -= size + 5;
    }
  }

  void row(List<String> cells, {bool bold = false}) {
    final wrapped = [
      for (var i = 0; i < _columns.length; i++)
        wrapText(cells[i], _columns[i].$2),
    ];
    final height =
        wrapped.fold<int>(1, (most, c) => c.length > most ? c.length : most);
    need(height * 13);
    final start = y;
    for (var i = 0; i < _columns.length; i++) {
      y = start;
      for (final line in wrapped[i]) {
        put(line, _columns[i].$1, 10, bold);
        y -= 13;
      }
    }
    y = start - height * 13;
  }

  final wording = document.wording;
  text(wording['schoolName'] ?? '', size: 18, bold: true);
  for (final key in ['address', 'contact', 'accreditation']) {
    text(wording[key] ?? '');
  }
  y -= 10;
  rule();
  y -= 14;
  text(document.title, size: 14, bold: true);
  y -= 6;
  for (final detail in document.details) {
    if (detail.value.trim().isNotEmpty) {
      text('${detail.label}: ${detail.value}', size: 11);
    }
  }

  for (final section in document.sections) {
    // Keeps a heading with its first lines.
    need(80);
    y -= 12;
    text(section.heading, size: 12, bold: true);
    y -= 2;
    row(_headings, bold: true);
    rule();
    y -= 3;
    for (final r in section.rows) {
      // A long table repeats its headings on the next page.
      if (y - 39 < _bottom) {
        newPage();
        row(_headings, bold: true);
        rule();
        y -= 3;
      }
      row([r.unit, r.coursework, r.uhpab, r.grade, r.points]);
    }
    if (section.summary.trim().isNotEmpty) text(section.summary, bold: true);
  }

  need(130);
  y -= 30;
  for (final key in ['signatory1', 'signatory2']) {
    final who = wording[key]?.trim() ?? '';
    if (who.isEmpty) continue;
    text('$who: ______________________   Date: ____________', size: 11);
    y -= 22;
  }
  text(wording['footer'] ?? '', size: 9);

  for (var i = 0; i < pages.length; i++) {
    y = 30;
    pages[i].writeln('BT /F1 8 Tf 500 $y Td '
        '(Page ${i + 1} of ${pages.length}) Tj ET');
  }
  return _assemble([for (final page in pages) page.toString()]);
}

Uint8List _assemble(List<String> pages) {
  const font = '<< /Type /Font /Subtype /Type1 /Encoding /WinAnsiEncoding '
      '/BaseFont /Helvetica';
  // Objects 1 to 4 are fixed; then a page and its contents for each page.
  final kids = [
    for (var i = 0; i < pages.length; i++) '${5 + i * 2} 0 R',
  ].join(' ');
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>',
    '$font >>',
    '$font-Bold >>',
    for (var i = 0; i < pages.length; i++) ...[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
          '/Contents ${6 + i * 2} 0 R >>',
      '<< /Length ${pages[i].length} >>\nstream\n${pages[i]}endstream',
    ],
  ];
  // Every character is one byte, so string lengths are byte offsets.
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return latin1.encode(pdf.toString());
}

/// Escapes a PDF string. Long dashes and curly quotes become plain ones, and
/// other characters the font cannot show become "?".
String _pdfText(String value) {
  final plain = value
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[“”]'), '"');
  return String.fromCharCodes([
    for (final c in plain.runes)
      (c >= 32 && c < 127) || (c >= 160 && c <= 255) ? c : 63,
  ]).replaceAllMapped(RegExp(r'[\\()]'), (m) => '\\${m[0]}');
}
