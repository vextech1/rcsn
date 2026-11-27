/// The roles in the RCSN Mobile App.
///
/// Each role has a distinct entry method and is never inferred from
/// context: a screen or provider should always know explicitly which role
/// it is serving.
enum UserRole {
  /// The one school Principal. Creates and suspends staff accounts and has
  /// oversight of everything else. Created by the bootstrap script, never
  /// in-app.
  principal,

  /// The one Deputy Principal. Has the Principal's responsibilities (staff
  /// management, announcements, oversight) but cannot touch the Principal,
  /// and only the Principal can terminate them. Created by the Principal.
  deputyPrincipal,

  /// Academic registrar / DOS. Builds academic structure, assigns tutors,
  /// admits students and manages academic status. Created by the Principal
  /// or Deputy Principal.
  registrar,

  /// Bursar. Records fee payments and balances. Created by the Principal or
  /// Deputy Principal.
  bursar,

  /// Any other member of staff, in a position the Principal or Deputy
  /// Principal added to the list (Askari, Accountant, Clinical Instructor,
  /// ...). The position's name is stored on the staff record as `position`.
  /// Has no management powers of its own.
  staffMember,

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
      case UserRole.deputyPrincipal:
        return 'Deputy Principal';
      case UserRole.registrar:
        return 'Registrar';
      case UserRole.bursar:
        return 'Bursar';
      case UserRole.staffMember:
        return 'Staff';
      case UserRole.tutor:
        return 'Tutor';
      case UserRole.student:
        return 'Student';
    }
  }

  /// True for the roles that live in the shared `staff` collection and
  /// sign in through the staff login.
  bool get isStaff =>
      this == UserRole.principal ||
      this == UserRole.deputyPrincipal ||
      this == UserRole.registrar ||
      this == UserRole.bursar ||
      this == UserRole.staffMember;

  /// Principal or Deputy Principal: the two roles that manage staff and
  /// have school-wide oversight.
  bool get isPrincipalLevel =>
      this == UserRole.principal || this == UserRole.deputyPrincipal;

  /// May publish to the Public Space directly (no review). Mirrors
  /// `isPostingStaff()` in firestore.rules.
  bool get canPublishPublicly =>
      isPrincipalLevel ||
      this == UserRole.registrar ||
      this == UserRole.bursar;

  /// May approve, archive and delete Public Space posts. Mirrors the
  /// moderator checks in firestore.rules.
  bool get canModeratePublic => isPrincipalLevel || this == UserRole.registrar;

  /// Firestore collection where this role's account records live. Kept
  /// here so a rename only ever happens in one place.
  String get collectionName {
    switch (this) {
      case UserRole.principal:
      case UserRole.deputyPrincipal:
      case UserRole.registrar:
      case UserRole.bursar:
      case UserRole.staffMember:
        return 'staff';
      case UserRole.tutor:
        return 'tutors';
      case UserRole.student:
        return 'students';
    }
  }
}
