import 'package:flutter_test/flutter_test.dart';
import 'package:rcsn_mobile_app/core/constants/academic_structure.dart';
import 'package:rcsn_mobile_app/core/constants/course_catalogue.dart';

void main() {
  const track = ProgramType.certificateNursing;

  test('every listed class exists and codes are unique', () {
    final ids = <String>[];
    kCourseCatalogue.forEach((programType, classes) {
      classes.forEach((key, units) {
        final semesters = kTrackDefinitions[programType]!.semestersPerYear;
        expect(key.$2, lessThanOrEqualTo(semesters[key.$1]!));
        ids.addAll(units.map((u) => standardSubjectId(programType, u)));
      });
    });
    expect(ids.toSet(), hasLength(ids.length));
    // Three papers and a practical in each of the five semesters.
    kTrackDefinitions[track]!.semestersPerYear.forEach((year, count) {
      for (var semester = 1; semester <= count; semester++) {
        expect(
          standardUnits(track, year, semester).map((u) => u.code),
          [for (var n = 1; n <= 4; n++) 'CN $year$semester$n'],
        );
      }
    });
  });

  test('a unit is recognised however it was added', () {
    final unit = standardUnits(track, 1, 2)[0]; // Anatomy II
    bool has(String id, String name) =>
        hasUnit(track, unit, [(id: id, name: name)]);
    expect(has('certificateNursing_CN121', 'Renamed'), isTrue);
    expect(has('abc', ' anatomy and physiology ii'), isTrue);
    expect(has('abc', 'CN121 Anatomy'), isTrue);
    expect(has('abc', 'Anatomy'), isFalse);
    final practical = standardUnits(track, 2, 1)[3];
    expect(
      hasUnit(track, practical, [(id: 'abc', name: 'Practicals')]),
      isFalse,
    );
  });
}
