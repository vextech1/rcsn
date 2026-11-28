enum CaseStatus {
  open('Open'),
  underReview('Under review'),
  closed('Closed');

  final String label;
  const CaseStatus(this.label);
}

/// A disciplinary case against one student.
class DisciplineCase {
  final String id;
  final String nsin;

  /// YYYY-MM-DD.
  final String date;
  final String offence;

  /// Empty until action has been taken.
  final String action;
  final CaseStatus status;

  /// Whether the student can see it.
  final bool visible;

  const DisciplineCase({
    required this.id,
    required this.nsin,
    required this.date,
    required this.offence,
    this.action = '',
    this.status = CaseStatus.open,
    this.visible = false,
  });

  /// The limit on the offence and the action. The rules check the same.
  static const int maxText = 500;

  factory DisciplineCase.fromMap(String id, String nsin, Map data) =>
      DisciplineCase(
        id: id,
        nsin: nsin,
        date: data['date'] as String,
        offence: data['offence'] as String,
        action: data['action'] as String? ?? '',
        status: CaseStatus.values.asNameMap()[data['status']] ?? CaseStatus.open,
        visible: data['visible'] == true,
      );

  /// What the student is shown.
  Map<String, Object> toStudentMap() => {
        'date': date,
        'offence': offence,
        'action': action,
        'status': status.name,
      };

  DisciplineCase withVisible(bool value) => DisciplineCase(
        id: id,
        nsin: nsin,
        date: date,
        offence: offence,
        action: action,
        status: status,
        visible: value,
      );

  /// Newest first.
  static List<DisciplineCase> sorted(List<DisciplineCase> cases) =>
      [...cases]..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : b.id.compareTo(a.id);
        });
}
