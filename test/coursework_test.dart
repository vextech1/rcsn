import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/data/models/coursework.dart';

void main() {
  const full = <String, double>{
    'practical': 5,
    'assignments': 2.5,
    'tests': 2.5,
    'clinical': 5,
    'recordBook': 5,
  };

  test('the parts add up to the coursework maximum', () {
    expect(
      kCourseworkParts.fold<int>(0, (sum, p) => sum + p.max),
      kCourseworkMax,
    );
  });

  test('a complete total below half is a retake', () {
    expect(const CourseworkMarks(full).total, 20);
    expect(const CourseworkMarks(full).isRetake, isFalse);
    final below = CourseworkMarks({...full, 'tests': 2.4});
    expect(below.total, 19.9);
    expect(below.isRetake, isTrue);
  });

  test('adding decimals does not turn a pass into a retake', () {
    const marks = CourseworkMarks({
      'practical': 4.1,
      'assignments': 2.2,
      'tests': 3.4,
      'clinical': 5.6,
      'recordBook': 4.7,
    });
    expect(marks.total, 20);
    expect(marks.isRetake, isFalse);
  });

  test('unfinished marks are never a retake', () {
    const marks = CourseworkMarks({'tests': 1});
    expect(marks.isComplete, isFalse);
    expect(marks.isRetake, isFalse);
  });

  test('typed marks are checked against the weight', () {
    final tests = kCourseworkParts.firstWhere((p) => p.key == 'tests');
    for (final ok in ['', '0', '5', '4.5']) {
      expect(CourseworkMarks.errorFor(tests, ok), isNull, reason: ok);
    }
    for (final bad in ['6', '5.1', '-1', '4.55', 'a', '4,5']) {
      expect(CourseworkMarks.errorFor(tests, bad), isNotNull, reason: bad);
    }
  });

  test('only known numeric marks are read', () {
    final marks = CourseworkMarks.fromMap({'tests': 4, 'exam': 50});
    expect(marks.values, {'tests': 4.0});
  });
}
