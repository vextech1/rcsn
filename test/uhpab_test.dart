import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/data/models/uhpab.dart';

void main() {
  UhpabUnit unit(double mark) => UhpabUnit(
        subjectId: 's',
        subjectName: 'CN 111',
        year: 1,
        semester: 1,
        mark: mark,
      );

  test('grades follow the national scale', () {
    const expected = {
      100.0: 'A', 80.0: 'A', 79.9: 'B+', 75.0: 'B+', 70.0: 'B',
      65.0: 'C+', 60.0: 'C', 55.0: 'D+', 50.0: 'D', 49.9: 'F', 0.0: 'F',
    };
    for (final entry in expected.entries) {
      expect(unit(entry.key).grade.letter, entry.value, reason: '${entry.key}');
    }
  });

  test('only a mark below 50 is a retake', () {
    expect(unit(50).isRetake, isFalse);
    expect(unit(49.9).isRetake, isTrue);
    expect(unit(45).summary, '45 · F · Retake');
  });

  test('typed marks are out of 100', () {
    for (final ok in ['0', '49.5', '100']) {
      expect(UhpabUnit.markError(ok), isNull, reason: ok);
    }
    for (final bad in ['', '101', '-1', '50.25', 'x']) {
      expect(UhpabUnit.markError(bad), isNotNull, reason: bad);
    }
  });

  test('file names cannot change the storage path', () {
    expect(UhpabDocument.safeName('a/b\\c.pdf'), 'a_b_c.pdf');
    expect(UhpabDocument.safeName('..'), 'result');
    expect(UhpabDocument.safeName('${'x' * 200}.pdf').length, 120);
    expect(UhpabDocument.safeName('${'x' * 200}.pdf'), endsWith('.pdf'));
  });

  test('a held answer carries nothing', () {
    final results = UhpabResults.fromWorker(
      {'blocked': true, 'units': [], 'documents': []},
    );
    expect(results.blocked, isTrue);
    expect(results.isEmpty, isTrue);
  });
}
