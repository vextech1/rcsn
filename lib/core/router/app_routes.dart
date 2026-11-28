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

  // Timetables and calendars. The Registrar edits; everyone else reads.
  static const String registrarTimetables = '/registrar/timetables';
  static const String registrarTimetableEditPattern = '/registrar/timetables/:id';
  static String registrarTimetableEdit(String id) => '/registrar/timetables/$id';
  static const String timetableViewPattern = '/timetable/:id';
  static String timetableView(String id) => '/timetable/$id';
  static const String studentTimetables = '/student/timetables';
  static const String tutorTimetables = '/tutor/timetables';

  // First-run setup: until the Principal has registered, these are the only
  // routes the router allows.
  static const String setupCheck = '/setup/check';
  static const String setup = '/setup';

  // Public space (no login needed to read; staff and tutors can post)
  static const String publicHome = '/public';
  static const String publicPost = '/public/post';
  static const String publicNew = '/public/new';
  static const String publicReview = '/public/review';

  // Staff: everyone who is not a Tutor or Student. They pick a position
  // first, then share one login. Custom positions (Askari, Accountant, ...)
  // land on staffHome.
  static const String staffPositions = '/staff/positions';
  static const String staffLogin = '/staff/login';
  static const String staffHome = '/staff/home';

  // Principal
  static const String principalDashboard = '/principal/dashboard';
  static const String principalStaff = '/principal/staff';
  static const String principalFees = '/principal/fees';
  static const String principalFeeRecord = '/principal/fees/record';

  // Registrar. The structure/tutors/students/content-types screens are
  // still the original Admin screens, relocated here in Phase 1 and
  // rebuilt for the Registrar in Phase 2. The Principal can also open
  // them for now (see the guard in app_router.dart).
  static const String registrarDashboard = '/registrar/dashboard';
  static const String registrarStructure = '/registrar/structure';
  static const String registrarTutors = '/registrar/tutors';
  static const String registrarStudents = '/registrar/students';
  static const String registrarContentTypes = '/registrar/content-types';
  static const String registrarStudentBio = '/registrar/students/bio';
  static const String registrarStudentDetail = '/registrar/students/detail';
  static const String registrarCoursework = '/registrar/coursework';
  static const String registrarStudentNumber = '/registrar/student-number';

  // Bursar
  static const String bursarDashboard = '/bursar/dashboard';
  static const String bursarAdd = '/bursar/add';
  static const String bursarBulk = '/bursar/class-tuition';
  static const String bursarRecord = '/bursar/record';

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
  // Outside /student: parents need only the NSIN or the payment code.
  static const String feeLookup = '/fee-lookup';
  static const String studentFees = '/student/fees';
  static const String studentResults = '/student/results';
  static const String studentUhpab = '/student/uhpab';
  static const String registrarUhpab = '/registrar/students/uhpab';
  static const String bursarResultAccess = '/bursar/results-access';
  static const String studentSettings = '/student/settings';
  static const String studentAccountInactive = '/student/account-inactive';
}
