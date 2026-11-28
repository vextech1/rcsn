/// A UHPAB grade on the scale used across Uganda.
class UhpabGrade {
  final String letter;
  final double points;
  final double from;

  const UhpabGrade(this.letter, this.points, this.from);

  static const List<UhpabGrade> scale = [
    UhpabGrade('A', 5.0, 80),
    UhpabGrade('B+', 4.5, 75),
    UhpabGrade('B', 4.0, 70),
    UhpabGrade('C+', 3.5, 65),
    UhpabGrade('C', 3.0, 60),
    UhpabGrade('D+', 2.5, 55),
    UhpabGrade('D', 2.0, 50),
    UhpabGrade('F', 0.0, 0),
  ];

  static UhpabGrade of(double mark) =>
      scale.firstWhere((g) => mark >= g.from, orElse: () => scale.last);
}

/// A mark below this is a retake.
const double kUhpabPass = 50;

/// A typed UHPAB mark for one course unit.
class UhpabUnit {
  final String subjectId;
  final String subjectName;
  final int year;
  final int semester;
  final double mark;
  final bool published;

  const UhpabUnit({
    required this.subjectId,
    required this.subjectName,
    required this.year,
    required this.semester,
    required this.mark,
    this.published = false,
  });

  /// Null if [text] is a mark out of 100 with at most one decimal.
  static String? markError(String text) {
    final value = text.trim();
    final mark = RegExp(r'^\d{1,3}(\.\d)?$').hasMatch(value)
        ? double.parse(value)
        : null;
    return mark == null || mark > 100 ? 'Enter a mark from 0 to 100' : null;
  }

  factory UhpabUnit.fromMap(String subjectId, Map data) => UhpabUnit(
        subjectId: subjectId,
        subjectName: data['subjectName'] as String,
        year: (data['year'] as num).toInt(),
        semester: (data['semester'] as num).toInt(),
        mark: (data['mark'] as num).toDouble(),
        published: data['published'] == true,
      );

  Map<String, Object> toMap() => {
        'subjectName': subjectName,
        'year': year,
        'semester': semester,
        'mark': mark,
        'published': published,
      };

  UhpabUnit withPublished(bool value) => UhpabUnit(
        subjectId: subjectId,
        subjectName: subjectName,
        year: year,
        semester: semester,
        mark: mark,
        published: value,
      );

  UhpabGrade get grade => UhpabGrade.of(mark);

  bool get isRetake => mark < kUhpabPass;

  String get markLabel => mark == mark.roundToDouble()
      ? mark.toStringAsFixed(0)
      : mark.toStringAsFixed(1);

  /// For example `45 · F · Retake`.
  String get summary =>
      '$markLabel · ${grade.letter}${isRetake ? ' · Retake' : ''}';
}

/// A result document uploaded to one student.
class UhpabDocument {
  final String id;

  /// The stored file name.
  final String name;
  final String title;
  final bool published;

  const UhpabDocument({
    required this.id,
    required this.name,
    required this.title,
    this.published = false,
  });

  factory UhpabDocument.fromMap(String id, Map data) => UhpabDocument(
        id: id,
        name: data['name'] as String,
        title: data['title'] as String,
        published: data['published'] == true,
      );

  Map<String, Object> toMap() =>
      {'name': name, 'title': title, 'published': published};

  UhpabDocument withPublished(bool value) => UhpabDocument(
        id: id,
        name: name,
        title: title,
        published: value,
      );

  /// [fileName] made safe to use as the last part of a storage path.
  static String safeName(String fileName) {
    final cleaned = fileName.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_').trim();
    final name = cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'result'
        : cleaned;
    // Keeps the end, where the extension is.
    return name.length <= 120 ? name : name.substring(name.length - 120);
  }
}

/// Everything UHPAB on record for one student, in class order.
class UhpabResults {
  /// The student has results, but unpaid fees hold them.
  final bool blocked;
  final List<UhpabUnit> units;
  final List<UhpabDocument> documents;

  UhpabResults({
    this.blocked = false,
    List<UhpabUnit> units = const [],
    List<UhpabDocument> documents = const [],
  })  : units = [...units]..sort((a, b) {
            if (a.year != b.year) return b.year - a.year;
            if (a.semester != b.semester) return b.semester - a.semester;
            return a.subjectName.compareTo(b.subjectName);
          }),
        // Ids are upload times, so newest first.
        documents = [...documents]..sort((a, b) => b.id.compareTo(a.id));

  factory UhpabResults.fromRecord(Map<String, dynamic>? data) {
    final units = data?['units'] as Map? ?? const {};
    final documents = data?['documents'] as Map? ?? const {};
    return UhpabResults(
      units: [
        for (final e in units.entries)
          UhpabUnit.fromMap(e.key as String, e.value as Map),
      ],
      documents: [
        for (final e in documents.entries)
          UhpabDocument.fromMap(e.key as String, e.value as Map),
      ],
    );
  }

  /// The Worker's answer to a student: published items only.
  factory UhpabResults.fromWorker(Map<String, dynamic> data) => UhpabResults(
        blocked: data['blocked'] == true,
        units: [
          for (final u in data['units'] as List)
            UhpabUnit.fromMap((u as Map)['subjectId'] as String, u),
        ],
        documents: [
          for (final d in data['documents'] as List)
            UhpabDocument.fromMap((d as Map)['id'] as String, d),
        ],
      );

  bool get isEmpty => units.isEmpty && documents.isEmpty;
}
