/// The five roles in the RCSN Mobile App.
///
/// Each role has a distinct entry method and is never inferred from
/// context: a screen or provider should always know explicitly which role
/// it is serving.
enum UserRole {
  /// The one school Principal. Creates and suspends staff accounts and has
  /// oversight of everything else. Created by the bootstrap script, never
  /// in-app.
  principal,

  /// Academic registrar / DOS. Builds academic structure, assigns tutors,
  /// admits students and manages academic status. Created by the Principal.
  registrar,

  /// Bursar. Records fee payments and balances. Created by the Principal.
  bursar,

  /// Self-registers (name, email, password). Has no subject access until
  /// assigned by the Registrar and cannot self-assign.
  tutor,

  /// No registration, no password. Pre-registered at admission; enters the
  /// app by NSIN only.
  student,
}

extension UserRoleInfo on UserRole {
  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case UserRole.principal:
        return 'Principal';
      case UserRole.registrar:
        return 'Registrar';
      case UserRole.bursar:
        return 'Bursar';
      case UserRole.tutor:
        return 'Tutor';
      case UserRole.student:
        return 'Student';
    }
  }

  /// True for the three roles that live in the shared `staff` collection
  /// and sign in through the staff login.
  bool get isStaff =>
      this == UserRole.principal ||
      this == UserRole.registrar ||
      this == UserRole.bursar;

  /// Firestore collection where this role's account records live. Kept
  /// here so a rename only ever happens in one place.
  String get collectionName {
    switch (this) {
      case UserRole.principal:
      case UserRole.registrar:
      case UserRole.bursar:
        return 'staff';
      case UserRole.tutor:
        return 'tutors';
      case UserRole.student:
        return 'students';
    }
  }
}
