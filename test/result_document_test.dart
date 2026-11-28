import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/core/constants/academic_structure.dart';
import 'package:rcsn_mobile_app/core/utils/result_pdf.dart';
import 'package:rcsn_mobile_app/data/models/coursework.dart';
import 'package:rcsn_mobile_app/data/models/result_document.dart';
import 'package:rcsn_mobile_app/data/models/student_record.dart';
import 'package:rcsn_mobile_app/data/models/tutor_account.dart';
import 'package:rcsn_mobile_app/data/models/uhpab.dart';

void main() {
  final student = StudentRecord(
    id: '1',
    nsin: 'ABC/1',
    name: 'Mary (Achieng)',
    programType: ProgramType.certificateNursing,
    year: 1,
    semester: 2,
    status: AccountStatus.active,
    admittedAt: DateTime(2026),
  );

  UhpabUnit board(String id, int semester, double mark,
          {bool published = true}) =>
      UhpabUnit(
        subjectId: id,
        subjectName: 'Unit $id',
        year: 1,
        semester: semester,
        mark: mark,
        published: published,
      );

  const coursework = [
    CourseworkEntry(
      nsin: 'ABC/1',
      subjectId: 'a',
      subjectName: 'Unit a',
      programType: 'certificateNursing',
      year: 1,
      semester: 1,
      marks: CourseworkMarks({'practical': 8, 'clinical': 7}),
      published: true,
    ),
  ];

  ResultDocument build({(int, int)? only, List<UhpabUnit>? uhpab}) =>
      ResultDocument.build(
        student: student,
        template: DocumentTemplate.defaults,
        coursework: coursework,
        uhpab: uhpab ??
            [board('a', 1, 80), board('b', 1, 50), board('c', 2, 70)],
        issued: '28 November 2026',
        only: only,
      );

  String detail(ResultDocument d, String label) =>
      d.details.firstWhere((x) => x.label == label).value;

  test('a transcript joins coursework and UHPAB marks and averages points', () {
    final document = build();
    expect(document.title, 'Academic Transcript');
    expect(document.sections.length, 2);
    final first = document.sections.first;
    expect(first.rows.first.coursework, '15');
    expect(first.rows.first.grade, 'A');
    expect(first.summary, 'GPA: 3.50');
    expect(detail(document, 'CGPA'), '3.67');
  });

  test('a result slip has one semester and no CGPA', () {
    final slip = build(only: (1, 2));
    expect(slip.title, 'Semester Result Slip');
    expect(slip.sections.single.heading, 'Year 1, Semester 2');
    expect(slip.details.any((d) => d.label == 'CGPA'), isFalse);
  });

  test('drafts are left out', () {
    final document = build(uhpab: [board('z', 2, 90, published: false)]);
    expect(document.sections.length, 1);
    expect(document.sections.single.rows.single.uhpab, '');
  });

  test('the template keeps saved blanks and fills what is missing', () {
    final template = DocumentTemplate.fromMap({'address': ''});
    expect(template['address'], '');
    expect(template['schoolName'], 'Rakai Community School of Nursing');
  });

  test('the PDF carries edits and grows to several pages', () {
    final document = build();
    document.sections.first.rows.addAll([
      for (var i = 0; i < 100; i++) ResultRow(unit: 'Extra unit $i'),
    ]);
    final pdf = latin1.decode(resultPdf(document));
    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains(r'Mary \(Achieng\)'));
    expect(pdf, contains('Extra unit 99'));
    expect(pdf, contains('Page 3 of'));
    // The cross-reference table points at the objects.
    final start = int.parse(
      pdf.split('startxref\n').last.split('\n').first,
    );
    expect(pdf.substring(start), startsWith('xref'));
  });

  test('the school badge is placed on the first page', () {
    final logo = File('assets/images/school_logo.jpg').readAsBytesSync();
    expect(jpegSize(logo), (360, 360));
    final pdf = latin1.decode(resultPdf(build(), logo: logo));
    expect(pdf, contains('/Width 360 /Height 360'));
    expect(pdf, contains('/Logo Do'));
    expect(pdf, contains('We serve for better health'));
    // The image is carried byte for byte.
    expect(pdf, contains(latin1.decode(logo)));
  });

  test('a file that is not a JPEG is left out', () {
    final bytes = latin1.encode('not a picture');
    expect(jpegSize(bytes), isNull);
    final pdf = latin1.decode(resultPdf(build(), logo: bytes));
    expect(pdf, isNot(contains('/Logo')));
  });

  test('long text wraps without losing words', () {
    expect(wrapText('one two three', 7), ['one two', 'three']);
    expect(wrapText('abcdefgh', 3), ['abc', 'def', 'gh']);
    expect(wrapText('  ', 3), isEmpty);
  });
}
