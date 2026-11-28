/// Where a student is placed for clinical practice, typed by the Registrar.
class Placement {
  final String id;
  final String hospital;

  /// What the student is to do there.
  final String activities;

  /// What the student is to gain there.
  final String experience;

  /// YYYY-MM-DD.
  final String startDate;
  final String endDate;

  const Placement({
    required this.id,
    required this.hospital,
    required this.activities,
    required this.experience,
    required this.startDate,
    required this.endDate,
  });

  static const int maxHospital = 100;
  static const int maxText = 2000;

  /// Null if the placement does not end before it starts.
  static String? dateError(String start, String end) =>
      start.isNotEmpty && end.isNotEmpty && end.compareTo(start) < 0
          ? 'The end date is before the start date'
          : null;

  factory Placement.fromMap(String id, Map data) => Placement(
        id: id,
        hospital: data['hospital'] as String,
        activities: data['activities'] as String? ?? '',
        experience: data['experience'] as String? ?? '',
        startDate: data['startDate'] as String,
        endDate: data['endDate'] as String,
      );

  Map<String, Object> toMap() => {
        'hospital': hospital,
        'activities': activities,
        'experience': experience,
        'startDate': startDate,
        'endDate': endDate,
      };

  /// `Upcoming`, `Current` or `Completed` on the day [today].
  String stage(DateTime today) {
    final day = today.toIso8601String().substring(0, 10);
    if (day.compareTo(startDate) < 0) return 'Upcoming';
    return day.compareTo(endDate) > 0 ? 'Completed' : 'Current';
  }

  /// Latest first.
  static List<Placement> sorted(List<Placement> placements) =>
      [...placements]..sort((a, b) {
          final byDate = b.startDate.compareTo(a.startDate);
          return byDate != 0 ? byDate : b.id.compareTo(a.id);
        });
}
