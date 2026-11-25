/// Centralized route path constants.
///
/// Every navigable path in the app is declared here once — screens
/// navigate using these constants, never raw string literals, so a path
/// rename is a one-line change here rather than a find-and-replace across
/// every screen that links to it.
class AppRoutes {
  AppRoutes._();

  // Entry
  static const String welcome = '/';
  static const String roleSelect = '/role-select';

  // Admin
  static const String adminSetup = '/admin/setup';
  static const String adminLogin = '/admin/login';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminStructure = '/admin/structure';
  static const String adminTutors = '/admin/tutors';
  static const String adminStudents = '/admin/students';
  static const String adminContentTypes = '/admin/content-types';

  // Tutor
  static const String tutorRegister = '/tutor/register';
  static const String tutorLogin = '/tutor/login';
  static const String tutorDashboard = '/tutor/dashboard';
  static const String tutorNotAssigned = '/tutor/not-assigned';
  static const String tutorUpload = '/tutor/upload';
  static const String tutorArchive = '/tutor/archive';
  static const String tutorSubject = '/tutor/subject';
  static const String tutorAccountInactive = '/tutor/account-inactive';

  // Student
  static const String studentSearch = '/student/search';
  static const String studentDashboard = '/student/dashboard';
  static const String studentSubject = '/student/subject';
  static const String studentSettings = '/student/settings';
  static const String studentAccountInactive = '/student/account-inactive';
}
