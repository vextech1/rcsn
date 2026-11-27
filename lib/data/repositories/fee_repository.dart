import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/student_fee.dart';
import '../../core/constants/academic_structure.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/student_number.dart';

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

  CollectionReference<Map<String, dynamic>> get _numbers =>
      _firestore.collection('fee_numbers');

  /// The payment number already attached to this student, if any.
  Future<String?> numberFor(String nsin) async {
    if (nsin.trim().isEmpty) return null;
    final found = await _fees
        .where('nsin', isEqualTo: StudentNumber.normalize(nsin))
        .limit(1)
        .get();
    return found.docs.isEmpty
        ? null
        : StudentFee.fromFirestore(found.docs.first).paymentNumber;
  }

  DocumentReference<Map<String, dynamic>> _guardians(String paymentNumber) =>
      _firestore.collection('fee_guardians').doc(paymentNumber);

  /// Parent or guardian names, used to check a parent asking for the fees.
  Stream<List<String>> watchGuardians(String paymentNumber) =>
      _guardians(paymentNumber).snapshots().map(
            (doc) => List<String>.from(doc.data()?['names'] as List? ?? []),
          );

  /// One or two names. Blank ones are dropped.
  Future<void> setGuardians(String paymentNumber, List<String> names) {
    final kept = [
      for (final name in names)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    return _run(
      () => _guardians(StudentFee.normalizeNumber(paymentNumber))
          .set({'names': kept, ..._stamp()}),
    );
  }

  /// The latest records, straight from the server.
  Future<List<StudentFee>> recordsFor(String paymentNumber) => _fetch(
        _fees.where('paymentNumber', isEqualTo: paymentNumber),
      );

  /// Every record of one class: a programme, year and semester.
  Future<List<StudentFee>> classRecords(
    ProgramType programType,
    int year,
    int semester,
  ) =>
      _fetch(
        _fees
            .where('programType', isEqualTo: programType.name)
            .where('year', isEqualTo: year)
            .where('semester', isEqualTo: semester),
      );

  Future<List<StudentFee>> _fetch(Query<Map<String, dynamic>> query) async {
    try {
      final found = await query.get(const GetOptions(source: Source.server));
      return found.docs.map(StudentFee.fromFirestore).toList();
    } on FirebaseException {
      throw const FeeFailure(
        'Could not load the records. Check your connection and try again.',
      );
    }
  }

  /// Sets the same tuition on all of [records]. Payments are not touched.
  Future<void> setClassTuition(List<StudentFee> records, int tuition) =>
      _run(() async {
        // A Firestore batch holds at most 500 writes.
        for (var start = 0; start < records.length; start += 400) {
          final batch = _firestore.batch();
          for (final record in records.skip(start).take(400)) {
            batch.update(
              _fees.doc(record.id),
              {'tuition': tuition, ..._stamp()},
            );
          }
          await batch.commit();
        }
      });

  /// Opens a student's record for a semester, with nothing paid yet.
  Future<String> create({
    required String paymentNumber,
    required String nsin,
    required String name,
    required ProgramType programType,
    required int year,
    required int semester,
    required int tuition,
  }) async {
    final normalized = StudentNumber.normalize(nsin);
    final number = StudentFee.normalizeNumber(paymentNumber);
    final ref = _fees.doc(StudentFee.idFor(number, year, semester));
    final numberRef = _numbers.doc(number);
    final existing = await numberFor(normalized);
    if (existing != null && existing != number) {
      throw FeeFailure('This student already has payment number $existing.');
    }
    await _run(() => _firestore.runTransaction((tx) async {
          final owner = await tx.get(numberRef);
          if (owner.exists && owner.data()!['nsin'] != normalized) {
            throw const FeeFailure(
              'That payment code belongs to another student.',
            );
          }
          // With no NSIN to compare, the name is what tells students apart.
          if (owner.exists && normalized.isEmpty) {
            final others = await _fees
                .where('paymentNumber', isEqualTo: number)
                .limit(1)
                .get();
            if (others.docs.isNotEmpty &&
                (others.docs.first.data()['name'] as String).toLowerCase() !=
                    name.trim().toLowerCase()) {
              throw const FeeFailure(
                'That payment code belongs to another student.',
              );
            }
          }
          if ((await tx.get(ref)).exists) {
            throw const FeeFailure(
              'This student already has a record for that semester.',
            );
          }
          if (!owner.exists) {
            tx.set(numberRef, {'nsin': normalized, ..._stamp()});
          }
          tx.set(ref, {
            'paymentNumber': number,
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

  /// Attaches the NSIN a new student has now been given to every record under
  /// their payment number. Possible once only.
  Future<void> attachNsin(String paymentNumber, String nsin) async {
    final normalized = StudentNumber.normalize(nsin);
    final existing = await numberFor(normalized);
    if (existing != null) {
      throw FeeFailure('That student number already has payment code $existing.');
    }
    await _run(() async {
      final records = await _fees
          .where('paymentNumber', isEqualTo: paymentNumber)
          .get(const GetOptions(source: Source.server));
      final batch = _firestore.batch()
        ..update(_numbers.doc(paymentNumber), {
          'nsin': normalized,
          ..._stamp(),
        });
      for (final doc in records.docs) {
        batch.update(doc.reference, {'nsin': normalized, ..._stamp()});
      }
      await batch.commit();
    });
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
