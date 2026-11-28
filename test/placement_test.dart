import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/data/models/placement.dart';

void main() {
  const placement = Placement(
    id: 'a',
    hospital: 'Mulago',
    activities: 'Ward rounds',
    experience: 'Triage',
    startDate: '2026-12-01',
    endDate: '2026-12-14',
  );

  test('the stage follows the dates, both ends included', () {
    expect(placement.stage(DateTime(2026, 11, 30, 23)), 'Upcoming');
    expect(placement.stage(DateTime(2026, 12, 1)), 'Current');
    expect(placement.stage(DateTime(2026, 12, 14, 23)), 'Current');
    expect(placement.stage(DateTime(2026, 12, 15)), 'Completed');
  });

  test('a placement cannot end before it starts', () {
    expect(Placement.dateError('2026-12-02', '2026-12-01'), isNotNull);
    expect(Placement.dateError('2026-12-01', '2026-12-01'), isNull);
  });

  test('saved fields read back', () {
    final read = Placement.fromMap('a', placement.toMap());
    expect(read.toMap(), placement.toMap());
  });
}
