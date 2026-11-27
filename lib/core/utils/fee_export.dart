import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import '../../data/models/student_fee.dart';
import '../constants/academic_structure.dart';
import 'money.dart';

String _programme(StudentFee fee) =>
    kTrackDefinitions[fee.programType]?.label ?? fee.programType.name;

/// A spreadsheet of fee records. Starts with a byte order mark so that Excel
/// reads it as UTF-8.
Uint8List feesCsv(List<StudentFee> fees) {
  // Text a spreadsheet would run as a formula gets a leading apostrophe.
  String text(String value) {
    final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final lines = [
    'Name,Payment code,Student number,Programme,Year,Semester,Tuition,Paid,Balance,Status',
    for (final f in fees)
      [
        text(f.name),
        text(f.paymentNumber),
        text(f.nsin),
        text(_programme(f)),
        f.year,
        f.semester,
        f.tuition,
        f.paid,
        f.balance,
        text(f.status.label),
      ].join(','),
  ];
  return Uint8List.fromList(utf8.encode('﻿${lines.join('\r\n')}\r\n'));
}

/// The student's semesters, up to and including [fee]'s, that still owe money.
/// A clearance slip is only given when there are none.
List<StudentFee> owingUpTo(StudentFee fee, List<StudentFee> records) => [
      for (final r in records)
        if (r.paymentNumber == fee.paymentNumber &&
            (r.year < fee.year ||
                (r.year == fee.year && r.semester <= fee.semester)) &&
            r.balance > 0)
          r,
    ];

/// A one-page A4 clearance slip to print, sign and stamp.
Uint8List clearancePdf(StudentFee fee, DateTime issued) {
  final content = StringBuffer();
  var y = 780;
  void line(String value, {int size = 12, bool bold = false, int gap = 22}) {
    // Long values continue on the next line.
    var rest = value;
    do {
      var cut = rest.length;
      if (cut > 60) {
        final space = rest.lastIndexOf(' ', 60);
        cut = space > 0 ? space : 60;
      }
      content.writeln('BT /${bold ? 'F2' : 'F1'} $size Tf 60 $y Td '
          '(${_pdfText(rest.substring(0, cut))}) Tj ET');
      rest = rest.substring(cut).trimLeft();
      y -= gap;
    } while (rest.isNotEmpty);
  }

  line('Rakai Community School of Nursing', size: 18, bold: true, gap: 30);
  line('Tuition Clearance Slip', size: 14, bold: true, gap: 40);
  line('Name: ${fee.name}');
  line('Student number: ${fee.nsin.isEmpty ? 'Not yet given' : fee.nsin}');
  line('Payment code: ${fee.paymentNumber}');
  // The built-in PDF font has no long dash.
  line('Programme: ${_programme(fee).replaceAll('–', '-')}');
  line('Year ${fee.year}, Semester ${fee.semester}', gap: 34);
  line('Tuition: ${formatUgx(fee.tuition)}');
  line('Paid: ${formatUgx(fee.paid)}');
  if (fee.balance < 0) line('Credit: ${formatUgx(-fee.balance)}');
  y -= 12;
  line('Status: CLEARED', bold: true);
  line('Date issued: ${DateFormat('d MMM yyyy').format(issued)}', gap: 60);
  line('Bursar: ______________________________', gap: 40);
  line('Signature: ___________________________', gap: 60);
  line('Valid only with the Bursar\'s signature and the school stamp.', size: 10);

  const font = '<< /Type /Font /Subtype /Type1 /Encoding /WinAnsiEncoding '
      '/BaseFont /Helvetica';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
    '$font >>',
    '$font-Bold >>',
    '<< /Length ${content.length} >>\nstream\n${content}endstream',
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

/// Escapes a PDF string. Characters the font cannot show become "?".
String _pdfText(String value) => String.fromCharCodes([
      for (final c in value.runes)
        (c >= 32 && c < 127) || (c >= 160 && c <= 255) ? c : 63,
    ]).replaceAllMapped(RegExp(r'[\\()]'), (m) => '\\${m[0]}');
