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
    expect(standardUnits(track, 1, 1), hasLength(5));
    expect(standardUnits(track, 1, 2), hasLength(5));
  });

  test('a unit is recognised however it was added', () {
    final unit = standardUnits(track, 1, 1)[3]; // Microbiology
    bool has(String id, String name) =>
        hasUnit(track, unit, [(id: id, name: name)]);
    expect(has('certificateNursing_CN1104', 'Renamed'), isTrue);
    expect(has('abc', ' microbiology'), isTrue);
    expect(has('abc', 'CN1104 Microbiology'), isTrue);
    expect(has('abc', 'Anatomy'), isFalse);
  });
}
