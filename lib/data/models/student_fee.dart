import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/academic_structure.dart';

enum FeeStatus {
  notPaid('Not paid'),
  partlyPaid('Balance due'),
  cleared('Cleared');

  final String label;
  const FeeStatus(this.label);
}

/// One student's tuition for one semester, kept by the Bursar.
///
/// Lives in `student_fees`, never on the `students` document (see
/// StudentRecord's doc comment). Linked to the student by NSIN. Amounts are
/// whole Uganda shillings. Balance and status are always derived, so they
/// cannot disagree with the figures.
class StudentFee {
  final String id;
  final String nsin;
  final String name;
  final ProgramType programType;
  final int year;
  final int semester;
  final int tuition;
  final int paid;

  const StudentFee({
    required this.id,
    required this.nsin,
    required this.name,
    required this.programType,
    required this.year,
    required this.semester,
    required this.tuition,
    required this.paid,
  });

  /// One record per student per semester. The rules check this same shape.
  static String idFor(String nsin, int year, int semester) =>
      '${nsin.replaceAll('/', '_')}_Y${year}S$semester';

  /// Negative when the student has paid more than the tuition.
  int get balance => tuition - paid;

  FeeStatus get status {
    if (balance <= 0) return FeeStatus.cleared;
    return paid > 0 ? FeeStatus.partlyPaid : FeeStatus.notPaid;
  }

  factory StudentFee.fromMap(String id, Map<String, dynamic> data) {
    return StudentFee(
      id: id,
      nsin: data['nsin'] as String,
      name: data['name'] as String,
      programType: ProgramType.values.byName(data['programType'] as String),
      year: data['year'] as int,
      semester: data['semester'] as int,
      tuition: data['tuition'] as int,
      paid: data['paid'] as int,
    );
  }

  factory StudentFee.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      StudentFee.fromMap(doc.id, doc.data()!);
}

enum PaymentMethod {
  bank('Bank'),
  mobileMoney('Mobile money'),
  cash('Cash'),
  correction('Correction');

  final String label;
  const PaymentMethod(this.label);
}

/// A payment received outside the app. Never edited or deleted: a mistake is
/// fixed with a [PaymentMethod.correction] entry, which may be negative.
class FeePayment {
  final int amount;
  final PaymentMethod method;
  final String reference;
  final DateTime? recordedAt;

  const FeePayment({
    required this.amount,
    required this.method,
    required this.reference,
    this.recordedAt,
  });

  factory FeePayment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return FeePayment(
      amount: data['amount'] as int,
      method: PaymentMethod.values.byName(data['method'] as String),
      reference: data['reference'] as String,
      // Null for a moment while the server timestamp is pending.
      recordedAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
