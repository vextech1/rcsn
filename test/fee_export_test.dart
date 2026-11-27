import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/core/constants/academic_structure.dart';
import 'package:rcsn_mobile_app/core/utils/fee_export.dart';
import 'package:rcsn_mobile_app/data/models/student_fee.dart';

StudentFee fee({int semester = 1, int paid = 1000, String name = 'Mary'}) =>
    StudentFee(
      id: 'PN12345_Y1S$semester',
      paymentNumber: 'PN12345',
      nsin: '',
      name: name,
      programType: ProgramType.certificateNursing,
      year: 1,
      semester: semester,
      tuition: 1000,
      paid: paid,
    );

void main() {
  test('CSV quotes text and disarms formulas', () {
    final csv = utf8.decode(feesCsv([fee(name: '=Mary "M", A', paid: 1200)]));
    expect(csv, contains('"\'=Mary ""M"", A","PN12345"'));
    expect(csv, contains(',1000,1200,-200,"Cleared"'));
  });

  test('earlier balances block clearance, later ones do not', () {
    final first = fee(paid: 400);
    final second = fee(semester: 2);
    expect(owingUpTo(second, [first, second]), [first]);
    expect(owingUpTo(fee(), [fee(), fee(semester: 2, paid: 0)]), isEmpty);
  });

  test('clearance slip is a PDF with correct offsets', () {
    final pdf = latin1.decode(
      clearancePdf(fee(name: 'Ann (A) ł ${'long ' * 20}'), DateTime(2026)),
    );
    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains(r'Ann \(A\) ?'));
    final xref = int.parse(pdf.split('startxref\n')[1].split('\n').first);
    expect(pdf.substring(xref), startsWith('xref'));
    final offsets = RegExp(r'(\d{10}) 00000 n')
        .allMatches(pdf)
        .map((m) => int.parse(m[1]!))
        .toList();
    expect(offsets, hasLength(6));
    for (var i = 0; i < offsets.length; i++) {
      expect(pdf.substring(offsets[i]), startsWith('${i + 1} 0 obj'));
    }
  });
}
