/// The six academic tracks offered at RCSN.
///
/// Diploma Direct Entry and Diploma Extension are modeled as fully separate
/// tracks — not sub-options of one "Diploma" category — because they differ
/// in both duration and entry point (Direct: from Senior 6 / UACE. Extension:
/// from Certificate holders). See project document Section 3.
enum ProgramType {
  certificateMidwifery,
  certificateNursing,
  diplomaDirectMidwifery,
  diplomaDirectNursing,
  diplomaExtensionMidwifery,
  diplomaExtensionNursing,
}

/// Describes one academic track: its display name, total duration, and —
/// critically — how many semesters each of its years actually has.
///
/// This is the single fact that must never be hardcoded elsewhere as
/// "2 semesters per year": Certificate Year 3 and Diploma Extension Year 2
/// are half-years with only ONE semester. A blind default would silently
/// generate a phantom empty semester on those tracks. See Section 3.2.
class TrackDefinition {
  final ProgramType type;
  final String label;
  final String durationLabel;

  /// Maps year number -> semester count for that year.
  /// e.g. {1: 2, 2: 2, 3: 1} means Year 3 has only one semester.
  final Map<int, int> semestersPerYear;

  const TrackDefinition({
    required this.type,
    required this.label,
    required this.durationLabel,
    required this.semestersPerYear,
  });

  /// Total years in this track — derived from the map, not stored
  /// separately, so the two can never drift out of sync.
  int get totalYears => semestersPerYear.length;

  /// Semester count for a specific year. Throws if the year doesn't exist
  /// on this track (e.g. asking for Year 4 of a 3-year Diploma) — this is
  /// deliberately a hard failure, not a silent fallback to 2, since a
  /// silent fallback is exactly the bug this class exists to prevent.
  int semestersInYear(int year) {
    final count = semestersPerYear[year];
    if (count == null) {
      throw ArgumentError(
        'Year $year does not exist on track "$label" '
        '(valid years: ${semestersPerYear.keys.join(", ")})',
      );
    }
    return count;
  }
}

/// The definitive list of all six tracks, matching Section 3.1 of the
/// project document exactly. This is the one place these numbers are
/// declared — every dropdown, every Admin structure screen, every
/// validation check reads from here.
const Map<ProgramType, TrackDefinition> kTrackDefinitions = {
  ProgramType.certificateMidwifery: TrackDefinition(
    type: ProgramType.certificateMidwifery,
    label: 'Certificate – Midwifery',
    durationLabel: '2.5 years',
    semestersPerYear: {1: 2, 2: 2, 3: 1}, // Y3 half-year
  ),
  ProgramType.certificateNursing: TrackDefinition(
    type: ProgramType.certificateNursing,
    label: 'Certificate – Nursing',
    durationLabel: '2.5 years',
    semestersPerYear: {1: 2, 2: 2, 3: 1}, // Y3 half-year
  ),
  ProgramType.diplomaDirectMidwifery: TrackDefinition(
    type: ProgramType.diplomaDirectMidwifery,
    label: 'Diploma Direct Entry – Midwifery',
    durationLabel: '3 years',
    semestersPerYear: {1: 2, 2: 2, 3: 2},
  ),
  ProgramType.diplomaDirectNursing: TrackDefinition(
    type: ProgramType.diplomaDirectNursing,
    label: 'Diploma Direct Entry – Nursing',
    durationLabel: '3 years',
    semestersPerYear: {1: 2, 2: 2, 3: 2},
  ),
  ProgramType.diplomaExtensionMidwifery: TrackDefinition(
    type: ProgramType.diplomaExtensionMidwifery,
    label: 'Diploma Extension – Midwifery',
    durationLabel: '1.5 years',
    semestersPerYear: {1: 2, 2: 1}, // Y2 half-year
  ),
  ProgramType.diplomaExtensionNursing: TrackDefinition(
    type: ProgramType.diplomaExtensionNursing,
    label: 'Diploma Extension – Nursing',
    durationLabel: '1.5 years',
    semestersPerYear: {1: 2, 2: 1}, // Y2 half-year
  ),
};

/// Convenience lookup, used by dropdown widgets that need every track as
/// a flat list rather than a map.
List<TrackDefinition> get kAllTracks => kTrackDefinitions.values.toList();
