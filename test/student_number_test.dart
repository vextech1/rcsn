import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/core/utils/student_number.dart';

void main() {
  const old = '@@@##/U028/@@@/###';

  test('formats use # for digits, @ for letters and * for either', () {
    expect(StudentNumber.matches(' jan21/u028/ccn/002 ', old), isTrue);
    expect(StudentNumber.matches('JAN21/U028/CC/002', old), isFalse);
    expect(StudentNumber.matches('A1.9', '**.#'), isTrue);
    expect(StudentNumber.matches('A1x9', '**.#'), isFalse);
  });

  test('any one format is enough; none means any well-formed number', () {
    expect(StudentNumber.errorFor('26-004', [old, '##-###']), isNull);
    expect(StudentNumber.errorFor('26004', [old]), isNotNull);
    expect(StudentNumber.errorFor('26004', []), isNull);
    for (final bad in ['', 'AB', 'AB CD', 'A_12', '/123']) {
      expect(StudentNumber.errorFor(bad, []), isNotNull, reason: bad);
    }
  });

  test('formats are validated', () {
    expect(StudentNumber.formatError(old), isNull);
    expect(StudentNumber.formatError('[0-9]+'), isNotNull);
  });

  test('bio ids cannot collide with payment codes', () {
    expect(StudentNumber.bioKey('A/B/1'), 'A_B_1');
    expect(StudentNumber.bioKey('PN12345'), 'N_PN12345');
  });
}
