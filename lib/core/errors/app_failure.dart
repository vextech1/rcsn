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
          'No student record found for that student number. '
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
      : super('This file exceeds the 95 MB upload limit.');
}

class UnsupportedFileTypeFailure extends AppFailure {
  const UnsupportedFileTypeFailure()
      : super(
          'This file type is not supported. '
          'Allowed: images, PDF, Excel, and Word.',
        );
}

class UploadFailedFailure extends AppFailure {
  const UploadFailedFailure([String? detail])
      : super(detail ?? 'Upload failed. Please check your connection and try again.');
}

class DownloadFailedFailure extends AppFailure {
  const DownloadFailedFailure([String? detail])
      : super(detail ?? 'Download failed. Please check your connection and try again.');
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

/// Coursework could not be loaded or saved.
class CourseworkFailure extends AppFailure {
  const CourseworkFailure(super.message);
}

/// A fee record could not be saved.
class FeeFailure extends AppFailure {
  const FeeFailure(super.message);
}

// ---------------------------------------------------------------------
// Generic fallback
// ---------------------------------------------------------------------

class UnknownFailure extends AppFailure {
  const UnknownFailure([String? detail])
      : super(detail ?? 'Something went wrong. Please try again.');
}
