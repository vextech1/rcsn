import 'student_fee.dart';

/// A semester and its payments, as the Worker returns it to students and
/// parents.
class FeeView {
  final StudentFee fee;
  final List<FeePayment> payments;

  const FeeView(this.fee, this.payments);

  factory FeeView.fromJson(Map<String, dynamic> json) {
    final fee = StudentFee.fromMap(
      StudentFee.idFor(
        json['paymentNumber'] as String,
        json['year'] as int,
        json['semester'] as int,
      ),
      json,
    );
    return FeeView(fee, [
      for (final p in json['payments'] as List)
        FeePayment(
          amount: p['amount'] as int,
          method: PaymentMethod.values.byName(p['method'] as String),
          reference: p['reference'] as String,
          recordedAt:
              DateTime.tryParse(p['createdAt'] as String? ?? '')?.toLocal(),
        ),
    ]);
  }
}

/// The extra questions a parent, guardian or student without an NSIN chooses
/// two of. The names match `worker/src/fees.js`.
enum FeeQuestion {
  dateOfBirth("Student's date of birth"),
  address('Home district and village'),
  studentName("Student's full name"),
  primarySchool('Primary school attended'),
  secondarySchool('Secondary school attended');

  final String label;
  const FeeQuestion(this.label);
}
