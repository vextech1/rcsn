import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/student_fee.dart';
import '../../core/constants/academic_structure.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/nsin_validator.dart';

/// Bursar's tuition records. The Firestore rules are the real boundary; they
/// also require every change to `paid` to come with a matching payment entry.
class FeeRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  FeeRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _fees =>
      _firestore.collection('student_fees');

  Stream<List<StudentFee>> watchAll() => _fees.snapshots().map(
        (snap) => snap.docs.map(StudentFee.fromFirestore).toList()
          ..sort((a, b) {
            final byName =
                a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return byName != 0 ? byName : b.id.compareTo(a.id);
          }),
      );

  /// Null if the record does not exist.
  Stream<StudentFee?> watch(String feeId) => _fees.doc(feeId).snapshots().map(
        (doc) => doc.exists ? StudentFee.fromFirestore(doc) : null,
      );

  Stream<List<FeePayment>> watchPayments(String feeId) => _fees
      .doc(feeId)
      .collection('payments')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(FeePayment.fromFirestore).toList());

  /// Opens a student's record for a semester, with nothing paid yet.
  Future<String> create({
    required String nsin,
    required String name,
    required ProgramType programType,
    required int year,
    required int semester,
    required int tuition,
  }) async {
    final normalized = NsinValidator.normalize(nsin);
    final ref = _fees.doc(StudentFee.idFor(normalized, year, semester));
    await _run(() => _firestore.runTransaction((tx) async {
          if ((await tx.get(ref)).exists) {
            throw const FeeFailure(
              'This student already has a record for that semester.',
            );
          }
          tx.set(ref, {
            'nsin': normalized,
            'name': name.trim(),
            'programType': programType.name,
            'year': year,
            'semester': semester,
            'tuition': tuition,
            'paid': 0,
            ..._stamp(),
          });
        }));
    return ref.id;
  }

  Future<void> setTuition(String feeId, int tuition) => _run(
        () => _fees.doc(feeId).update({'tuition': tuition, ..._stamp()}),
      );

  /// Adds a payment and updates the total in one transaction.
  Future<void> recordPayment(String feeId, FeePayment payment) async {
    final feeRef = _fees.doc(feeId);
    final paymentRef = feeRef.collection('payments').doc();
    await _run(() => _firestore.runTransaction((tx) async {
          final snapshot = await tx.get(feeRef);
          if (!snapshot.exists) {
            throw const FeeFailure('This fee record no longer exists.');
          }
          final paid = StudentFee.fromFirestore(snapshot).paid + payment.amount;
          if (paid < 0) {
            throw const FeeFailure(
              'A correction cannot take the amount paid below zero.',
            );
          }
          tx.set(paymentRef, {
            'amount': payment.amount,
            'method': payment.method.name,
            'reference': payment.reference.trim(),
            'recordedBy': _uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.update(feeRef, {
            'paid': paid,
            'lastPaymentId': paymentRef.id,
            ..._stamp(),
          });
        }));
  }

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const UnauthorizedActionFailure('Please sign in again.');
    }
    return uid;
  }

  Map<String, dynamic> _stamp() => {
        'updatedBy': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw FeeFailure(
        e.code == 'permission-denied'
            ? 'You do not have permission to change fee records.'
            : 'Could not save. Check your connection and try again.',
      );
    }
  }
}
