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
    // Three papers and a practical in each of the five semesters, for both
    // certificates (codes read: prefix, year, semester, paper).
    const prefixes = {
      ProgramType.certificateNursing: 'CN',
      ProgramType.certificateMidwifery: 'CM',
    };
    prefixes.forEach((programType, prefix) {
      kTrackDefinitions[programType]!.semestersPerYear.forEach((year, count) {
        for (var semester = 1; semester <= count; semester++) {
          expect(
            standardUnits(programType, year, semester).map((u) => u.code),
            [for (var n = 1; n <= 4; n++) '$prefix $year$semester$n'],
            reason: '$prefix year $year semester $semester',
          );
        }
      });
    });
  });

  test('Certificate Midwifery units are as the curriculum lists them', () {
    const cm = ProgramType.certificateMidwifery;
    String title(int year, int semester, int paper) =>
        standardUnits(cm, year, semester)[paper - 1].title;

    expect(title(1, 1, 1), 'Anatomy and Physiology I and First Aid');
    expect(title(1, 1, 3), 'Personal and Community Health and Microbiology');
    expect(title(1, 2, 1), 'Anatomy and Physiology II');
    expect(title(2, 1, 1), 'Obstetric Anatomy');
    expect(title(2, 1, 2), 'Midwifery I and Pharmacology');
    expect(title(2, 2, 1), 'Midwifery II and Tropical Medicine');
    expect(title(2, 2, 2), 'Paediatric Nursing II and Pharmacology II');
    expect(title(3, 1, 1), 'Gynaecology and Reproductive Health');
    expect(title(3, 1, 2), 'Mental Health, Guidance and Counselling');

    // The practical in every semester is paper 4, listed as "Practicals".
    for (final (year, semester) in [(1, 1), (1, 2), (2, 1), (2, 2), (3, 1)]) {
      final practical = standardUnits(cm, year, semester)[3];
      expect(practical.code, 'CM $year${semester}4');
      expect(practical.title, 'Practicals');
    }

    // No asterisks or other footnote marks leak into titles.
    for (final classes in kCourseCatalogue.values) {
      for (final units in classes.values) {
        for (final unit in units) {
          expect(unit.title.contains('*'), isFalse, reason: unit.code);
        }
      }
    }
  });

  test('Midwifery and Nursing papers never collide', () {
    final nursing = standardUnits(ProgramType.certificateNursing, 1, 1)[0];
    final midwifery = standardUnits(ProgramType.certificateMidwifery, 1, 1)[0];
    expect(
      standardSubjectId(ProgramType.certificateNursing, nursing),
      isNot(standardSubjectId(ProgramType.certificateMidwifery, midwifery)),
    );
    // A Nursing subject in a Midwifery class is not mistaken for a CM unit.
    expect(
      hasUnit(ProgramType.certificateMidwifery, midwifery,
          [(id: 'certificateNursing_CN111', name: 'CN 111 Anatomy')]),
      isFalse,
    );
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
