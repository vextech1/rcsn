import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/data/models/attendance.dart';

void main() {
  Attendance at(double percent) => Attendance(
        subjectId: 's',
        subjectName: 'CN 111',
        year: 1,
        semester: 1,
        percent: percent,
      );

  test('only attendance below 85 is a warning', () {
    expect(at(85).isLow, isFalse);
    expect(at(84.9).isLow, isTrue);
  });

  test('typed values are percentages', () {
    for (final ok in ['', '0', '84.5', '100']) {
      expect(Attendance.errorFor(ok), isNull, reason: ok);
    }
    for (final bad in ['101', '-1', '90.55', 'x', '90%']) {
      expect(Attendance.errorFor(bad), isNotNull, reason: bad);
    }
  });

  test('saved fields read back', () {
    final read = Attendance.fromMap('s', at(90.5).toMap());
    expect(read.toMap(), at(90.5).toMap());
    expect(read.percentText, '90.5');
  });
}
