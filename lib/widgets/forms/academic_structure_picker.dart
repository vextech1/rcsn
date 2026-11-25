import 'package:flutter/material.dart';
import '../../core/constants/academic_structure.dart';

/// The single shared cascading Program → Year → Semester picker.
///
/// This widget exists specifically because the architecture plan called
/// out that this exact picker is reused in THREE separate places: Admin's
/// structure builder, Admin's student admission-entry form, and Admin's
/// tutor-assignment screen. Building it once, here, means a fix or
/// change to how tracks/years/semesters are selected happens in one
/// file — the alternative (three screens each rolling their own cascade
/// logic) is exactly how the kind of drift this whole project has been
/// careful to avoid (e.g. the per-year semester count) would eventually
/// creep back in through a UI-layer shortcut nobody meant to take.
///
/// Deliberately stateless from Firestore's perspective — this widget
/// doesn't read or write Subjects itself. It only knows how to let
/// someone pick a valid (track, year, semester) combination and reports
/// that selection upward via [onChanged]. The caller decides what to DO
/// with the selection (create a Subject, filter a query, assign a
/// tutor) — keeping that decision out of this widget is what makes it
/// safely reusable across three different purposes.
///
/// Semester options are correctly restricted per the selected track+year
/// — selecting Certificate + Year 3 offers ONLY Semester 1, not
/// Semester 1 and 2, because [kTrackDefinitions] says that year has one
/// semester. This is the concrete place where Section 3.2's "the Admin
/// structure-builder must allow the semester count to be set per year,
/// not defaulted to two everywhere" actually becomes a real UI
/// constraint rather than a rule someone has to remember to enforce
/// separately.
class AcademicStructurePicker extends StatefulWidget {
  final ProgramType? initialTrack;
  final int? initialYear;
  final int? initialSemester;
  final void Function(ProgramType? track, int? year, int? semester) onChanged;

  const AcademicStructurePicker({
    super.key,
    this.initialTrack,
    this.initialYear,
    this.initialSemester,
    required this.onChanged,
  });

  @override
  State<AcademicStructurePicker> createState() =>
      _AcademicStructurePickerState();
}

class _AcademicStructurePickerState extends State<AcademicStructurePicker> {
  ProgramType? _track;
  int? _year;
  int? _semester;

  @override
  void initState() {
    super.initState();
    _track = widget.initialTrack;
    _year = widget.initialYear;
    _semester = widget.initialSemester;
  }

  List<int> get _availableYears {
    final track = _track;
    if (track == null) return [];
    return kTrackDefinitions[track]!.semestersPerYear.keys.toList()..sort();
  }

  List<int> get _availableSemesters {
    final track = _track;
    final year = _year;
    if (track == null || year == null) return [];
    final count = kTrackDefinitions[track]!.semestersPerYear[year];
    if (count == null) return [];
    return List.generate(count, (i) => i + 1);
  }

  void _onTrackChanged(ProgramType? track) {
    setState(() {
      _track = track;
      // Changing the track invalidates any previously chosen year/
      // semester that may not exist on the new track — reset both
      // rather than risk an invalid combination silently surviving
      // the track change (same reasoning as StructureProvider.
      // selectTrack, mirrored here since this widget doesn't route
      // through that provider directly).
      _year = null;
      _semester = null;
    });
    widget.onChanged(_track, _year, _semester);
  }

  void _onYearChanged(int? year) {
    setState(() {
      _year = year;
      _semester = null;
    });
    widget.onChanged(_track, _year, _semester);
  }

  void _onSemesterChanged(int? semester) {
    setState(() => _semester = semester);
    widget.onChanged(_track, _year, _semester);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ProgramType>(
          initialValue: _track,
          decoration: const InputDecoration(labelText: 'Program / Track'),
          items: kAllTracks
              .map((t) => DropdownMenuItem(
                    value: t.type,
                    child: Text(t.label),
                  ))
              .toList(),
          onChanged: _onTrackChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _year,
          decoration: const InputDecoration(labelText: 'Year'),
          // Disabled (no items, no-op onChanged) until a track is picked
          // — rather than showing a Year dropdown with no meaningful
          // options before the track that determines them is known.
          items: _availableYears
              .map((y) => DropdownMenuItem(value: y, child: Text('Year $y')))
              .toList(),
          onChanged: _availableYears.isEmpty ? null : _onYearChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _semester,
          decoration: const InputDecoration(labelText: 'Semester'),
          // This is where a half-year track visibly has only one option
          // instead of two — Certificate Year 3 and Diploma Extension
          // Year 2 will show a single "Semester 1" entry here, correctly,
          // with no way to select a Semester 2 that doesn't exist.
          items: _availableSemesters
              .map((s) =>
                  DropdownMenuItem(value: s, child: Text('Semester $s')))
              .toList(),
          onChanged: _availableSemesters.isEmpty ? null : _onSemesterChanged,
        ),
      ],
    );
  }
}
