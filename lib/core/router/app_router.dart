import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_provider.dart';
import '../constants/user_role.dart';
import '../../screens/shared/welcome_screen.dart';
import '../../screens/shared/role_select_screen.dart';
import '../../screens/admin/setup/admin_setup_screen.dart';
import '../../screens/admin/auth/admin_login_screen.dart';
import '../../screens/admin/dashboard/admin_dashboard_screen.dart';
import '../../screens/admin/structure/admin_structure_screen.dart';
import '../../screens/admin/tutors/admin_tutors_screen.dart';
import '../../screens/admin/students/admin_students_screen.dart';
import '../../screens/admin/content_types/admin_content_types_screen.dart';
import '../../screens/tutor/auth/tutor_register_screen.dart';
import '../../screens/tutor/auth/tutor_login_screen.dart';
import '../../screens/tutor/dashboard/tutor_dashboard_screen.dart';
import '../../screens/tutor/dashboard/tutor_account_inactive_screen.dart';
import '../../screens/tutor/upload/tutor_upload_screen.dart';
import '../../screens/tutor/archive/tutor_archive_screen.dart';
import '../../screens/tutor/subject/tutor_subject_screen.dart';
import '../../screens/student/search/student_search_screen.dart';
import '../../screens/student/dashboard/student_dashboard_screen.dart';
import '../../screens/student/subject/student_subject_screen.dart';
import '../../screens/student/settings/student_settings_screen.dart';
import '../../screens/student/account_inactive/student_account_inactive_screen.dart';

// NOTE: this file still references placeholder screen widgets under
// lib/screens/ for Admin, Tutor, and Student routes — those batches
// haven't been built yet. The shared/ routes (Welcome, RoleSelect) were
// wired to their real screens as soon as those screens were written,
// rather than leaving them stale until every other screen batch is also
// done — the ROUTING LOGIC (paths, guards, redirect rules) was fully
// decided before any screen existed and hasn't changed here, only which
// widget each route's builder points to.

// NAVIGATION CONVENTION — push vs go, read before wiring any new screen:
// context.go() REPLACES the current location in GoRouter's stack rather
// than pushing onto it. Used for every forward navigation in this app at
// first, that left nothing for the Android/iOS back gesture to pop back
// to — pressing back from, say, AdminStructureScreen (reached via
// dashboard tile tap) fell straight through to closing the app, since
// there was no previous route in the stack. Fixed by switching ordinary
// forward drill-down navigation to context.push() instead, which DOES
// add to the stack and gets the back button/gesture and the AppBar's
// automatic back arrow working correctly.
//
// Rule of thumb for any screen added later (Tutor Upload/Archive,
// Student Dashboard/Subject, etc.):
//   - Drilling INTO something the user should be able to back out of
//     (dashboard → work-area screen, list → detail) → context.push()
//   - An auth-state transition that should NOT be back-able into
//     (setup complete → dashboard, sign-out → role select, a failed
//     first-run race redirecting to login) → context.go() is correct,
//     don't change these to push()
//   - Lateral swaps between peer entry screens (Tutor Login ↔ Register)
//     → context.go() is fine here too, to avoid the two screens
//     stacking indefinitely on repeated back-and-forth switches

/// Central router configuration.
///
/// The `redirect` callback below is what actually closes the client-side
/// half of the enforcement gap flagged repeatedly since the repositories
/// batch: a suspended tutor being unable to find a button to the upload
/// screen is not the same as a suspended tutor being unable to REACH the
/// upload screen (e.g. via a deep link, or a stale bookmark). This
/// redirect runs on every navigation attempt, not just the ones that
/// originate from an in-app button — that's the whole point of putting
/// this logic here rather than only checking account status inside each
/// screen's build method.
///
/// Still explicitly NOT a substitute for Firestore Security Rules: this
/// guards the Flutter app's OWN navigation. It does nothing to stop a
/// direct Firestore read/write that bypasses the app's UI entirely — that
/// boundary is still open, as noted throughout data/repositories/.
GoRouter buildAppRouter({
  required AuthProvider authProvider,
  required StudentProvider studentProvider,
}) {
  return GoRouter(
    initialLocation: AppRoutes.welcome,
    refreshListenable: Listenable.merge([authProvider, studentProvider]),
    redirect: (context, state) =>
        _guard(context, state, authProvider, studentProvider),
    routes: [
      // Shared entry routes — wired to their real screens.
      GoRoute(path: AppRoutes.welcome, builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: AppRoutes.roleSelect, builder: (_, __) => const RoleSelectScreen()),

      // Admin
      GoRoute(path: AppRoutes.adminSetup, builder: (_, __) => const AdminSetupScreen()),
      GoRoute(path: AppRoutes.adminLogin, builder: (_, __) => const AdminLoginScreen()),
      GoRoute(path: AppRoutes.adminDashboard, builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(path: AppRoutes.adminStructure, builder: (_, __) => const AdminStructureScreen()),
      GoRoute(path: AppRoutes.adminTutors, builder: (_, __) => const AdminTutorsScreen()),
      GoRoute(path: AppRoutes.adminStudents, builder: (_, __) => const AdminStudentsScreen()),
      GoRoute(path: AppRoutes.adminContentTypes, builder: (_, __) => const AdminContentTypesScreen()),

      // Tutor
      GoRoute(path: AppRoutes.tutorRegister, builder: (_, __) => const TutorRegisterScreen()),
      GoRoute(path: AppRoutes.tutorLogin, builder: (_, __) => const TutorLoginScreen()),
      GoRoute(path: AppRoutes.tutorDashboard, builder: (_, __) => const TutorDashboardScreen()),
      // Deliberately still a stub — never navigated to. See the class
      // doc comment on TutorDashboardScreen for why this route is dead:
      // the "not yet assigned" state is shown inline on the dashboard
      // itself, driven live by the assignments stream.
      GoRoute(path: AppRoutes.tutorNotAssigned, builder: (_, __) => const _Stub('TutorNotAssigned')),
      GoRoute(path: AppRoutes.tutorUpload, builder: (_, __) => const TutorUploadScreen()),
      GoRoute(path: AppRoutes.tutorArchive, builder: (_, __) => const TutorArchiveScreen()),
      GoRoute(path: AppRoutes.tutorSubject, builder: (_, __) => const TutorSubjectScreen()),
      GoRoute(path: AppRoutes.tutorAccountInactive, builder: (_, __) => const TutorAccountInactiveScreen()),

      // Student
      GoRoute(path: AppRoutes.studentSearch, builder: (_, __) => const StudentSearchScreen()),
      GoRoute(path: AppRoutes.studentDashboard, builder: (_, __) => const StudentDashboardScreen()),
      GoRoute(path: AppRoutes.studentSubject, builder: (_, __) => const StudentSubjectScreen()),
      GoRoute(path: AppRoutes.studentSettings, builder: (_, __) => const StudentSettingsScreen()),
      GoRoute(path: AppRoutes.studentAccountInactive, builder: (_, __) => const StudentAccountInactiveScreen()),
    ],
  );
}

String? _guard(
  BuildContext context,
  GoRouterState state,
  AuthProvider auth,
  StudentProvider student,
) {
  final path = state.matchedLocation;

  final isEntryRoute = path == AppRoutes.welcome || path == AppRoutes.roleSelect;
  final isAdminRoute = path.startsWith('/admin');
  final isTutorRoute = path.startsWith('/tutor');
  final isStudentRoute = path.startsWith('/student');

  // Public routes within each section that must stay reachable even
  // WITHOUT an active session — otherwise nobody could ever sign in or
  // register in the first place. Everything else in that section
  // requires the corresponding active session.
  final isAdminPublicRoute =
      path == AppRoutes.adminSetup || path == AppRoutes.adminLogin;
  final isTutorPublicRoute =
      path == AppRoutes.tutorRegister || path == AppRoutes.tutorLogin;
  final isStudentPublicRoute = path == AppRoutes.studentSearch;

  if (isEntryRoute) {
    if (auth.isResolving) return null;

    if (auth.resolvedRole == UserRole.admin) {
      return AppRoutes.adminDashboard;
    }

    if (auth.resolvedRole == UserRole.tutor) {
      if (auth.isUsableTutorSession) return AppRoutes.tutorDashboard;
      return AppRoutes.tutorAccountInactive;
    }

    return null;
  }

  // ---------------------------------------------------------------
  // ADMIN routes
  // ---------------------------------------------------------------
  if (isAdminRoute) {
    // Public routes (login, setup) — must stay reachable for
    // unauthenticated users, but redirect authenticated Admins away
    // so they don't get stuck on the login screen after signing in.
    if (isAdminPublicRoute) {
      if (auth.isResolving) return null;
      if (auth.resolvedRole == UserRole.admin) {
        return AppRoutes.adminDashboard;
      }
      return null;
    }

    if (auth.isResolving) return null;

    if (auth.resolvedRole != UserRole.admin) {
      return AppRoutes.adminLogin;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // TUTOR routes
  // ---------------------------------------------------------------
  if (isTutorRoute) {
    // Public routes (login, register) — must stay reachable for
    // unauthenticated users, but redirect authenticated Tutors away
    // so they don't get stuck on the login screen after signing in.
    if (isTutorPublicRoute) {
      if (auth.isResolving) return null;
      if (auth.resolvedRole == UserRole.tutor) {
        if (auth.isUsableTutorSession) return AppRoutes.tutorDashboard;
        return AppRoutes.tutorAccountInactive;
      }
      return null;
    }
    if (path == AppRoutes.tutorAccountInactive) return null;

    if (auth.isResolving) return null;

    if (auth.resolvedRole != UserRole.tutor) {
      return AppRoutes.tutorLogin;
    }

    if (!auth.isUsableTutorSession) {
      return AppRoutes.tutorAccountInactive;
    }

    return null;
  }

  // ---------------------------------------------------------------
  // STUDENT routes
  // ---------------------------------------------------------------
  if (isStudentRoute) {
    if (isStudentPublicRoute) return null;
    if (path == AppRoutes.studentAccountInactive) return null;
    if (path == AppRoutes.studentSettings) {
      // Settings must stay reachable even for an inactive session — this
      // is deliberate: it's where clearSession() lives (per the
      // borrowed-phone design), and a student whose session somehow
      // became unusable still needs a way to clear it and start over,
      // not get locked out of the one screen that could fix that.
      return null;
    }

    // Still restoring a persisted session from shared_preferences on
    // app startup — don't redirect yet, let the restoring state render
    // its own loading UI. Redirecting here would cause a flash to
    // studentSearch before a valid persisted session finishes loading.
    if (student.isRestoring) return null;

    if (!student.isUsableSession) {
      // Covers both "never searched" and "found but suspended/
      // terminated-course" — both cases correctly land back at NSIN
      // entry, since neither has a usable session to proceed with.
      return AppRoutes.studentSearch;
    }

    return null;
  }

  return null; // unrecognized path — let GoRouter's own 404 handling apply
}

/// Temporary placeholder widget so this router file is independently
/// complete and reviewable before lib/screens/ exists. Every GoRoute
/// above will have its builder swapped to the real screen widget in the
/// next batch — this class itself gets deleted at that point, it's not
/// meant to survive into the finished app.
class _Stub extends StatelessWidget {
  final String label;
  const _Stub(this.label);

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$label (stub — screen not yet built)'));
  }
}
