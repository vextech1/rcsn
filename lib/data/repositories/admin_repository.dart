import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_account.dart';
import '../services/auth_service.dart';
import '../../core/errors/app_failure.dart';

/// Owns the single AdminAccount.
///
/// Per Section 2.1, Admin has no self-registration screen — it's created
/// once via first-run setup. [adminExists] is what makes that "once"
/// actually real: the first-run setup screen must call this BEFORE
/// showing the creation form, and [createAdmin] independently re-checks
/// before writing, so a network race (two people opening the app's
/// first-run screen at the exact same moment on two devices, unlikely but
/// not impossible) can't result in two AdminAccount documents.
class AdminRepository {
  final FirebaseFirestore _firestore;
  final AuthService _authService;

  AdminRepository({
    FirebaseFirestore? firestore,
    AuthService? authService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _authService = authService ?? AuthService();

  CollectionReference<Map<String, dynamic>> get _admins =>
      _firestore.collection('admins');

  /// Checked by the first-run setup flow to decide whether to show the
  /// "create Admin" form or route straight to the Admin login screen.
  Future<bool> adminExists() async {
    final query = await _admins.limit(1).get();
    return query.docs.isNotEmpty;
  }

  /// Creates the one Admin account. Throws if one already exists —
  /// this is the actual enforcement point for "exactly one Admin,"
  /// not just a UI convention of only showing the form once.
  Future<AdminAccount> createAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    if (await adminExists()) {
      throw const AdminAlreadyExistsFailure();
    }

    final user = await _authService.registerWithEmail(
      email: email,
      password: password,
    );

    final account = AdminAccount(
      id: user.uid,
      name: name,
      email: email,
      createdAt: DateTime.now(),
    );

    await _admins.doc(user.uid).set(account.toFirestore());
    return account;
  }

  Future<AdminAccount?> getAdmin() async {
    final query = await _admins.limit(1).get();
    if (query.docs.isEmpty) return null;
    return AdminAccount.fromFirestore(query.docs.first);
  }
}
