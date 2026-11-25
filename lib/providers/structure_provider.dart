import 'package:flutter/foundation.dart';
import '../data/repositories/structure_repository.dart';
import '../data/models/subject.dart';
import '../core/constants/academic_structure.dart';
import '../core/errors/app_failure.dart';

/// Exposes the academic structure (Subjects) to the UI.
///
/// Deliberately thin — StructureRepository's streams already give live
/// Firestore data, and Firestore streams update automatically; this
/// provider's real job is holding the CURRENTLY SELECTED track/year/
/// semester as UI state (which dropdown values are picked right now)
/// alongside the underlying data streams, since that selection state has
/// nowhere else to live — it's not persisted, it's purely "what is the
/// Admin looking at right now."
///
/// This is also the shared provider behind the reusable Program→Class→
/// Year→Semester dropdown widget (widgets/forms/ — not yet built), used
/// in three separate places per the architecture tree: Admin's structure
/// builder, Admin's student admission-entry, and Admin's tutor-assignment
/// screen. Building the selection logic once here, rather than three
/// times inside three screens, is why this provider exists rather than
/// each screen just calling StructureRepository directly.
class StructureProvider extends ChangeNotifier {
  final StructureRepository _repository;

  StructureProvider({StructureRepository? repository})
      : _repository = repository ?? StructureRepository();

  ProgramType? _selectedTrack;
  int? _selectedYear;
  int? _selectedSemester;
  AppFailure? _lastError;
  bool _isSubmitting = false;

  ProgramType? get selectedTrack => _selectedTrack;
  int? get selectedYear => _selectedYear;
  int? get selectedSemester => _selectedSemester;
  AppFailure? get lastError => _lastError;
  bool get isSubmitting => _isSubmitting;

  /// Valid years for whichever track is currently selected — the
  /// dropdown widget reads this to populate its Year options, rather
  /// than hardcoding "1, 2, 3" and hoping it happens to match. Empty
  /// list if no track is selected yet.
  List<int> get availableYears {
    final track = _selectedTrack;
    if (track == null) return [];
    return kTrackDefinitions[track]!.semestersPerYear.keys.toList()..sort();
  }

  /// Valid semesters for the currently selected track+year — this is
  /// where the half-year tracks actually surface in the UI: selecting
  /// Certificate + Year 3 makes this return [1], not [1, 2], so the
  /// dropdown simply has nothing to offer for a semester that doesn't
  /// exist rather than needing a separate validation error later.
  List<int> get availableSemesters {
    final track = _selectedTrack;
    final year = _selectedYear;
    if (track == null || year == null) return [];
    final count = kTrackDefinitions[track]!.semestersPerYear[year];
    if (count == null) return [];
    return List.generate(count, (i) => i + 1);
  }

  void selectTrack(ProgramType? track) {
    _selectedTrack = track;
    // Changing the track invalidates any previously selected year/semester
    // that might not exist on the new track — reset both rather than risk
    // an invalid combination silently surviving the track change.
    _selectedYear = null;
    _selectedSemester = null;
    notifyListeners();
  }

  void selectYear(int? year) {
    _selectedYear = year;
    _selectedSemester = null; // same reasoning as selectTrack above
    notifyListeners();
  }

  void selectSemester(int? semester) {
    _selectedSemester = semester;
    notifyListeners();
  }

  void resetSelection() {
    _selectedTrack = null;
    _selectedYear = null;
    _selectedSemester = null;
    notifyListeners();
  }

  Stream<List<Subject>> watchSubjectsForTrack(ProgramType track) {
    return _repository.watchSubjectsForTrack(track);
  }

  Stream<List<Subject>> watchAllSubjects() => _repository.watchAllSubjects();

  Future<void> createSubject(String name) async {
    if (_selectedTrack == null ||
        _selectedYear == null ||
        _selectedSemester == null) {
      _lastError = const UnknownFailure(
        'Select a track, year, and semester before creating a subject.',
      );
      notifyListeners();
      return;
    }

    _isSubmitting = true;
    _lastError = null;
    notifyListeners();

    try {
      await _repository.createSubject(
        name: name,
        programType: _selectedTrack!,
        year: _selectedYear!,
        semester: _selectedSemester!,
      );
    } on AppFailure catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
