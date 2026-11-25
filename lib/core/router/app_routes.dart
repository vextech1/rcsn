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

  // Staff (Principal, Registrar, Bursar share one login)
  static const String staffLogin = '/staff/login';

  // Principal
  static const String principalDashboard = '/principal/dashboard';
  static const String principalStaff = '/principal/staff';

  // Registrar. The structure/tutors/students/content-types screens are
  // still the original Admin screens, relocated here in Phase 1 and
  // rebuilt for the Registrar in Phase 2. The Principal can also open
  // them for now (see the guard in app_router.dart).
  static const String registrarDashboard = '/registrar/dashboard';
  static const String registrarStructure = '/registrar/structure';
  static const String registrarTutors = '/registrar/tutors';
  static const String registrarStudents = '/registrar/students';
  static const String registrarContentTypes = '/registrar/content-types';

  // Bursar
  static const String bursarDashboard = '/bursar/dashboard';

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
