import 'package:flutter/material.dart';
import 'timetable.dart';

/// Ready-made starting points for the Registrar. Each builds a normal
/// [Timetable] that can then be changed freely: rows, columns, colours,
/// headers and footnotes are all editable.
enum TimetableTemplate {
  classWeek(
    'Class timetable',
    'Days across, periods down, with break and lunch rows',
    Icons.schedule,
  ),
  exam(
    'Exam timetable',
    'Date, day, time, subject, venue and invigilator',
    Icons.assignment,
  ),
  semesterCalendar(
    'Semester calendar',
    'Week by week, Monday to Friday, with a notes column',
    Icons.date_range,
  ),
  schoolCalendar(
    'School calendar',
    'Terms and semesters with start and end dates, key dates and notes',
    Icons.calendar_month,
  ),
  blank(
    'Blank grid',
    'A plain grid to design from scratch',
    Icons.grid_on,
  );

  final String label;
  final String description;
  final IconData icon;
  const TimetableTemplate(this.label, this.description, this.icon);
}

const int _headerBg = 0xFF1F4E5F; // brand teal
const int _white = 0xFFFFFFFF;
const int _labelBg = 0xFFE8EEF0;
const int _breakBg = 0xFFFFF3CD;

TimetableCell _header(String text) => TimetableCell(
      text: text,
      bg: _headerBg,
      fg: _white,
      bold: true,
      align: 1,
    );

TimetableCell _label(String text) =>
    TimetableCell(text: text, bg: _labelBg, bold: true);

TimetableCell _break(String text) =>
    TimetableCell(text: text, bg: _breakBg, italic: true, align: 1);

Timetable buildTemplate(TimetableTemplate template) {
  final cells = <String, TimetableCell>{};
  void put(int r, int c, TimetableCell cell) => cells[Timetable.key(r, c)] = cell;

  switch (template) {
    case TimetableTemplate.classWeek:
      const days = ['Time', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
      for (var c = 0; c < days.length; c++) {
        put(0, c, _header(days[c]));
      }
      const periods = [
        '8:00 – 9:00',
        '9:00 – 10:00',
        '10:00 – 10:30',
        '10:30 – 11:30',
        '11:30 – 12:30',
        '12:30 – 2:00',
        '2:00 – 3:00',
        '3:00 – 4:00',
      ];
      for (var r = 0; r < periods.length; r++) {
        put(r + 1, 0, _label(periods[r]));
      }
      for (var c = 1; c < days.length; c++) {
        put(3, c, _break(c == 3 ? 'Break' : ''));
        put(6, c, _break(c == 3 ? 'Lunch' : ''));
      }
      return Timetable(
        title: 'Class Timetable',
        type: TimetableType.classTimetable,
        rows: periods.length + 1,
        cols: days.length,
        colWidths: const [110, 130, 130, 130, 130, 130],
        cells: cells,
      );

    case TimetableTemplate.exam:
      const heads = ['Date', 'Day', 'Time', 'Course / Subject', 'Venue', 'Invigilator'];
      for (var c = 0; c < heads.length; c++) {
        put(0, c, _header(heads[c]));
      }
      return Timetable(
        title: 'Examination Timetable',
        type: TimetableType.exam,
        rows: 11,
        cols: heads.length,
        colWidths: const [100, 90, 110, 200, 130, 150],
        cells: cells,
        footnotes: const ['Candidates must arrive 30 minutes before the paper.'],
      );

    case TimetableTemplate.semesterCalendar:
      const heads = ['Week', 'Dates', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Notes'];
      for (var c = 0; c < heads.length; c++) {
        put(0, c, _header(heads[c]));
      }
      for (var w = 1; w <= 16; w++) {
        put(w, 0, _label('Week $w'));
      }
      return Timetable(
        title: 'Semester Calendar',
        type: TimetableType.semesterCalendar,
        rows: 17,
        cols: heads.length,
        colWidths: const [80, 140, 100, 100, 100, 100, 100, 220],
        cells: cells,
      );

    case TimetableTemplate.schoolCalendar:
      const heads = ['Term / Semester', 'Starts', 'Ends', 'Key dates', 'Notes'];
      for (var c = 0; c < heads.length; c++) {
        put(0, c, _header(heads[c]));
      }
      const labels = [
        'Semester 1',
        'Mid-semester break',
        'Semester 2',
        'Examinations',
        'Holidays',
        'Graduation',
      ];
      for (var r = 0; r < labels.length; r++) {
        put(r + 1, 0, _label(labels[r]));
      }
      return Timetable(
        title: 'School Calendar',
        type: TimetableType.calendar,
        rows: labels.length + 1,
        cols: heads.length,
        colWidths: const [160, 110, 110, 240, 200],
        cells: cells,
      );

    case TimetableTemplate.blank:
      for (var c = 0; c < 5; c++) {
        put(0, c, _header(''));
      }
      return Timetable(
        title: 'Untitled',
        type: TimetableType.custom,
        rows: 8,
        cols: 5,
        colWidths: List<int>.filled(5, Timetable.defaultColWidth),
        cells: cells,
      );
  }
}
