/// Base class for all typed failures in the app. Repositories and services
/// throw these instead of raw exceptions, so screens can catch specific
/// failure types and show the right message rather than a generic
/// "something went wrong."
abstract class AppFailure implements Exception {
  final String message;
  const AppFailure(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------
// Auth failures
// ---------------------------------------------------------------------

class AuthFailure extends AppFailure {
  const AuthFailure(super.message);
}

class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure()
      : super('Incorrect email or password. Please try again.');
}

class AccountSuspendedFailure extends AuthFailure {
  const AccountSuspendedFailure()
      : super('This account has been suspended. Please contact the Principal or Registrar.');
}

class AccountTerminatedFailure extends AuthFailure {
  const AccountTerminatedFailure()
      : super('This account has been terminated.');
}

/// A staff-management action (create, suspend, reactivate, invite) failed.
class StaffManagementFailure extends AppFailure {
  const StaffManagementFailure(super.message);
}

// ---------------------------------------------------------------------
// Student NSIN lookup failures — Section 2.3
// ---------------------------------------------------------------------

class NsinNotFoundFailure extends AppFailure {
  const NsinNotFoundFailure()
      : super(
          'No student record found for that NSIN. '
          'Please check the number or contact Admin.',
        );
}

// ---------------------------------------------------------------------
// Permission failures — Section 2.4
// ---------------------------------------------------------------------

class NotAssignedFailure extends AppFailure {
  const NotAssignedFailure()
      : super(
          'You have not been assigned to any subjects yet. '
          'Please contact Admin.',
        );
}

class UnauthorizedActionFailure extends AppFailure {
  const UnauthorizedActionFailure([String? detail])
      : super(detail ?? 'You do not have permission to perform this action.');
}

// ---------------------------------------------------------------------
// Upload failures — Section 4.1
// ---------------------------------------------------------------------

class FileTooLargeFailure extends AppFailure {
  const FileTooLargeFailure()
      : super('This file exceeds the 100MB upload limit.');
}

class UnsupportedFileTypeFailure extends AppFailure {
  const UnsupportedFileTypeFailure()
      : super(
          'This file type is not supported. '
          'Allowed: images, PDF, Excel, Word, and video.',
        );
}

class UploadFailedFailure extends AppFailure {
  const UploadFailedFailure([String? detail])
      : super(detail ?? 'Upload failed. Please check your connection and try again.');
}

class CompressionFailedFailure extends AppFailure {
  const CompressionFailedFailure()
      : super('Video compression failed before upload. Please try again.');
}

// ---------------------------------------------------------------------
// Structure failures — Section 3.3 (structure dependency)
// ---------------------------------------------------------------------

class StructureNotFoundFailure extends AppFailure {
  const StructureNotFoundFailure()
      : super(
          'The academic structure has not been set up yet. '
          'Please contact Admin.',
        );
}

// ---------------------------------------------------------------------
// Generic fallback
// ---------------------------------------------------------------------

class UnknownFailure extends AppFailure {
  const UnknownFailure([String? detail])
      : super(detail ?? 'Something went wrong. Please try again.');
}
