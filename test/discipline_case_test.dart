import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/data/models/discipline_case.dart';

void main() {
  DisciplineCase item(String id, String date) =>
      DisciplineCase(id: id, nsin: 'A/1', date: date, offence: 'Late');

  test('the student copy leaves out the private flag', () {
    expect(item('a', '2026-01-01').toStudentMap().keys, [
      'date',
      'offence',
      'action',
      'status',
    ]);
  });

  test('a new case is hidden and open', () {
    final created = item('a', '2026-01-01');
    expect(created.visible, isFalse);
    expect(created.status, CaseStatus.open);
  });

  test('an unknown status reads as open', () {
    final read = DisciplineCase.fromMap('a', 'A/1', {
      'date': '2026-01-01',
      'offence': 'Late',
      'status': 'something',
    });
    expect(read.status, CaseStatus.open);
  });

  test('newest first', () {
    final sorted = DisciplineCase.sorted(
      [item('a', '2026-01-01'), item('b', '2026-03-01')],
    );
    expect([for (final c in sorted) c.id], ['b', 'a']);
  });
}
