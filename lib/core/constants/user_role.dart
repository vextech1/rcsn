/// The three user roles in the RCSN Mobile App.
///
/// Per the project document (Section 2), each role has a distinct entry
/// method into the app and is never inferred from context — a screen or
/// provider should always know explicitly which role it's serving.
enum UserRole {
  /// Exactly one Admin account exists, created once via first-run setup.
  /// Builds academic structure, assigns tutors, manages account status.
  /// See Section 2.1.
  admin,

  /// Self-registers (name, email, password). Has no subject access until
  /// assigned by Admin — cannot self-assign. See Section 2.2.
  tutor,

  /// No registration, no password. Pre-registered at admission by Admin;
  /// enters the app via NSIN lookup only. See Section 2.3.
  student,
}

/// Human-readable label for UI display (role-select screen, admin lists).
extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.tutor:
        return 'Tutor';
      case UserRole.student:
        return 'Student';
    }
  }

  /// Firestore collection name where this role's account records live.
  /// Kept here — not re-typed as a string literal in repositories — so a
  /// rename only ever happens in one place.
  String get collectionName {
    switch (this) {
      case UserRole.admin:
        return 'admins';
      case UserRole.tutor:
        return 'tutors';
      case UserRole.student:
        return 'students';
    }
  }
}
