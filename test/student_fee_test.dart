import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/core/utils/money.dart';
import 'package:rcsn_mobile_app/data/models/student_fee.dart';

StudentFee fee(int tuition, int paid) => StudentFee.fromMap('id', {
      'nsin': 'JAN26/U028/MCK/001',
      'name': 'Mary',
      'programType': 'certificateNursing',
      'year': 1,
      'semester': 1,
      'tuition': tuition,
      'paid': paid,
    });

void main() {
  test('balance and status follow the figures', () {
    expect(fee(100, 0).status, FeeStatus.notPaid);
    expect(fee(100, 40).status, FeeStatus.partlyPaid);
    expect(fee(100, 40).balance, 60);
    expect(fee(100, 100).status, FeeStatus.cleared);
    expect(fee(100, 130).status, FeeStatus.cleared);
    expect(fee(100, 130).balance, -30);
  });

  test('one record id per student per semester', () {
    expect(StudentFee.idFor('JAN26/U028/MCK/001', 2, 1),
        'JAN26_U028_MCK_001_Y2S1');
  });

  test('money input', () {
    expect(parseUgx('1,500,000'), 1500000);
    expect(parseUgx('12.5'), isNull);
    expect(parseUgx('-5'), isNull);
    expect(parseUgx('-5', allowNegative: true), -5);
    expect(formatUgx(1500000), 'UGX 1,500,000');
  });
}
