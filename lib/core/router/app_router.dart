import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../providers/student_provider.dart';
import '../constants/user_role.dart';
import '../../screens/shared/welcome_screen.dart';
import '../../screens/shared/role_select_screen.dart';
import '../../screens/setup/principal_setup_screen.dart';
import '../../screens/setup/setup_check_screen.dart';
import '../../data/models/public_post.dart';
import '../../data/models/staff_position.dart';
import '../../screens/public/public_home_screen.dart';
import '../../screens/public/public_post_detail_screen.dart';
import '../../screens/public/public_compose_screen.dart';
import '../../screens/public/public_review_screen.dart';
import '../../screens/registrar/timetables/timetable_editor_screen.dart';
import '../../screens/registrar/timetables/timetable_list_screen.dart';
import '../../screens/registrar/timetables/timetable_viewer_screen.dart';
import '../../screens/staff/auth/staff_login_screen.dart';
import '../../screens/staff/auth/staff_position_screen.dart';
import '../../screens/staff/dashboard/staff_member_dashboard_screen.dart';
import '../../screens/principal/dashboard/principal_dashboard_screen.dart';
import '../../screens/principal/staff/principal_staff_screen.dart';
import '../../screens/registrar/dashboard/registrar_dashboard_screen.dart';
import '../../screens/registrar/bio/student_bio_screen.dart';
import '../../screens/admin/students/student_detail_screen.dart';
import '../../data/models/student_record.dart';
import '../../screens/registrar/student_number/student_number_format_screen.dart';
import '../../screens/bursar/add/bursar_add_fee_screen.dart';
import '../../screens/bursar/bulk/bursar_bulk_tuition_screen.dart';
import '../../data/models/student_fee.dart';
import '../../screens/student/fees/student_fees_screen.dart';
import '../../screens/bursar/detail/bursar_fee_detail_screen.dart';
import '../../screens/bursar/dashboard/bursar_dashboard_screen.dart';
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
  required SetupProvider setupProvider,
}) {
  return GoRouter(
    initialLocation: AppRoutes.welcome,
    refreshListenable:
        Listenable.merge([authProvider, studentProvider, setupProvider]),
    redirect: (context, state) =>
        _guard(context, state, authProvider, studentProvider, setupProvider),
    routes: [
      // First-run setup (the only routes reachable before the Principal
      // has registered).
      GoRoute(path: AppRoutes.setupCheck, builder: (_, __) => const SetupCheckScreen()),
      GoRoute(path: AppRoutes.setup, builder: (_, __) => const PrincipalSetupScreen()),

      // Shared entry routes — wired to their real screens.
      GoRoute(path: AppRoutes.welcome, builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: AppRoutes.roleSelect, builder: (_, __) => const RoleSelectScreen()),

      // Timetables and calendars
      GoRoute(
        path: AppRoutes.registrarTimetables,
        builder: (context, __) => TimetableListScreen(
          mode: context.read<AuthProvider>().resolvedRole == UserRole.registrar
              ? TimetableListMode.registrar
              : TimetableListMode.principal,
        ),
      ),
      GoRoute(
        path: AppRoutes.registrarTimetableEditPattern,
        builder: (_, state) =>
            TimetableEditorScreen(timetableId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.timetableViewPattern,
        builder: (_, state) =>
            TimetableViewerScreen(timetableId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.studentTimetables,
        builder: (_, __) => const TimetableListScreen(mode: TimetableListMode.student),
      ),
      GoRoute(
        path: AppRoutes.tutorTimetables,
        builder: (_, __) => const TimetableListScreen(mode: TimetableListMode.staff),
      ),

      // Public space
      GoRoute(path: AppRoutes.publicHome, builder: (_, __) => const PublicHomeScreen()),
      GoRoute(
        path: AppRoutes.publicPost,
        // The post travels as `extra`; if it is lost (e.g. the route is
        // rebuilt without it) fall back to the public home instead of
        // crashing.
        builder: (_, state) {
          final post = state.extra;
          return post is PublicPost
              ? PublicPostDetailScreen(post: post)
              : const PublicHomeScreen();
        },
      ),
      GoRoute(path: AppRoutes.publicNew, builder: (_, __) => const PublicComposeScreen()),
      GoRoute(path: AppRoutes.publicReview, builder: (_, __) => const PublicReviewScreen()),

      // Staff
      GoRoute(path: AppRoutes.staffPositions, builder: (_, __) => const StaffPositionScreen()),
      GoRoute(
        path: AppRoutes.staffLogin,
        // The picked position travels as `extra`. It is null when the
        // router sent the user here (a signed-out visit to a staff-only
        // screen); sign-in then works without a position check.
        builder: (_, state) {
          final extra = state.extra;
          return StaffLoginScreen(
            position: extra is StaffPosition ? extra : null,
          );
        },
      ),
      GoRoute(path: AppRoutes.staffHome, builder: (_, __) => const StaffMemberDashboardScreen()),

      // Principal
      GoRoute(path: AppRoutes.principalDashboard, builder: (_, __) => const PrincipalDashboardScreen()),
      GoRoute(path: AppRoutes.principalStaff, builder: (_, __) => const PrincipalStaffScreen()),
      GoRoute(path: AppRoutes.principalFees, builder: (_, __) => const BursarDashboardScreen(readOnly: true)),
      GoRoute(
        path: AppRoutes.principalFeeRecord,
        builder: (_, state) {
          final extra = state.extra;
          return extra is String
              ? BursarFeeDetailScreen(feeId: extra, readOnly: true)
              : const BursarDashboardScreen(readOnly: true);
        },
      ),

      // Registrar (work screens are still the original Admin screens)
      GoRoute(path: AppRoutes.registrarDashboard, builder: (_, __) => const RegistrarDashboardScreen()),
      GoRoute(path: AppRoutes.registrarStructure, builder: (_, __) => const AdminStructureScreen()),
      GoRoute(path: AppRoutes.registrarTutors, builder: (_, __) => const AdminTutorsScreen()),
      GoRoute(path: AppRoutes.registrarStudents, builder: (_, __) => const AdminStudentsScreen()),
      GoRoute(path: AppRoutes.registrarContentTypes, builder: (_, __) => const AdminContentTypesScreen()),

      GoRoute(
        path: AppRoutes.registrarStudentDetail,
        builder: (_, state) {
          final extra = state.extra;
          return extra is StudentRecord
              ? StudentDetailScreen(student: extra)
              : const AdminStudentsScreen();
        },
      ),
      GoRoute(
        path: AppRoutes.registrarStudentBio,
        // The student travels as `extra`; without it, show the list.
        builder: (_, state) {
          final extra = state.extra;
          return extra is ({String bioKey, String label})
              ? StudentBioScreen(bioKey: extra.bioKey, label: extra.label)
              : const AdminStudentsScreen();
        },
      ),
      GoRoute(path: AppRoutes.registrarStudentNumber, builder: (_, __) => const StudentNumberFormatScreen()),

      // Bursar
      GoRoute(path: AppRoutes.bursarBulk, builder: (_, __) => const BursarBulkTuitionScreen()),
      GoRoute(path: AppRoutes.bursarDashboard, builder: (_, __) => const BursarDashboardScreen()),
      GoRoute(
        path: AppRoutes.bursarAdd,
        builder: (_, state) {
          final extra = state.extra;
          return BursarAddFeeScreen(from: extra is StudentFee ? extra : null);
        },
      ),
      GoRoute(
        path: AppRoutes.bursarRecord,
        // The record id travels as `extra`; without it, show the list.
        builder: (_, state) {
          final extra = state.extra;
          return extra is String
              ? BursarFeeDetailScreen(feeId: extra)
              : const BursarDashboardScreen();
        },
      ),

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
      GoRoute(path: AppRoutes.feeLookup, builder: (_, __) => const StudentFeesScreen(lookup: true)),
      GoRoute(path: AppRoutes.studentFees, builder: (_, __) => const StudentFeesScreen()),
      GoRoute(path: AppRoutes.studentSettings, builder: (_, __) => const StudentSettingsScreen()),
      GoRoute(path: AppRoutes.studentAccountInactive, builder: (_, __) => const StudentAccountInactiveScreen()),
    ],
  );
}

/// Where a signed-in staff member lands after login.
String _staffHome(UserRole role) {
  switch (role) {
    case UserRole.principal:
    case UserRole.deputyPrincipal:
      return AppRoutes.principalDashboard;
    case UserRole.registrar:
      return AppRoutes.registrarDashboard;
    case UserRole.bursar:
      return AppRoutes.bursarDashboard;
    case UserRole.staffMember:
      return AppRoutes.staffHome;
    case UserRole.tutor:
    case UserRole.student:
      return AppRoutes.staffLogin;
  }
}

String? _guard(
  BuildContext context,
  GoRouterState state,
  AuthProvider auth,
  StudentProvider student,
  SetupProvider setup,
) {
  final path = state.matchedLocation;

  // First-run gate, before anything else: until the Principal has
  // registered, the app shows nothing but the setup screens. firestore.rules
  // enforce the same rule server-side.
  switch (setup.status) {
    case SetupStatus.checking:
    case SetupStatus.error:
      return path == AppRoutes.setupCheck ? null : AppRoutes.setupCheck;
    case SetupStatus.needsSetup:
      return path == AppRoutes.setup ? null : AppRoutes.setup;
    case SetupStatus.ready:
      if (path == AppRoutes.setup || path == AppRoutes.setupCheck) {
        return AppRoutes.welcome;
      }
  }

  final isEntryRoute = path == AppRoutes.welcome || path == AppRoutes.roleSelect;
  // The position list and the login are both "not signed in yet" screens.
  final isStaffLogin =
      path == AppRoutes.staffLogin || path == AppRoutes.staffPositions;
  final isStaffHomeRoute = path == AppRoutes.staffHome;
  final isPrincipalRoute = path.startsWith('/principal');
  final isRegistrarRoute = path.startsWith('/registrar');
  final isBursarRoute = path.startsWith('/bursar');
  final isTutorRoute = path.startsWith('/tutor');
  final isStudentRoute = path.startsWith('/student');

  // Public routes within each section that must stay reachable even
  // WITHOUT an active session, otherwise nobody could ever sign in or
  // register. Everything else in that section requires the matching
  // active session.
  final isTutorPublicRoute =
      path == AppRoutes.tutorRegister || path == AppRoutes.tutorLogin;
  final isStudentPublicRoute = path == AppRoutes.studentSearch;

  if (isEntryRoute) {
    if (auth.isResolving) return null;

    if (auth.resolvedRole != null && auth.resolvedRole!.isStaff) {
      return _staffHome(auth.resolvedRole!);
    }

    if (auth.resolvedRole == UserRole.tutor) {
      if (auth.isUsableTutorSession) return AppRoutes.tutorDashboard;
      return AppRoutes.tutorAccountInactive;
    }

    // A student whose saved NSIN has been re-resolved on launch goes
    // straight in, same as a signed-in tutor or staff member. While the
    // saved session is still being restored, stay put; the provider's
    // notifyListeners() re-runs this guard when it finishes.
    if (!student.isRestoring) {
      if (student.isUsableSession) return AppRoutes.studentDashboard;
      if (student.currentStudent != null) {
        return AppRoutes.studentAccountInactive;
      }
    }

    return null;
  }

  // ---------------------------------------------------------------
  // STAFF login (shared by Principal, Registrar, Bursar)
  // ---------------------------------------------------------------
  if (isStaffLogin) {
    if (auth.isResolving) return null;
    if (auth.isUsableStaffSession) return _staffHome(auth.resolvedRole!);
    return null;
  }

  // ---------------------------------------------------------------
  // PRINCIPAL / REGISTRAR / BURSAR routes
  // ---------------------------------------------------------------
  if (isPrincipalRoute || isRegistrarRoute || isBursarRoute) {
    if (auth.isResolving) return null;
    if (!auth.isUsableStaffSession) return AppRoutes.staffLogin;

    final role = auth.resolvedRole!;
    // The Deputy Principal has the Principal's screens and access.
    final allowed = isPrincipalRoute
        ? role.isPrincipalLevel
        : isBursarRoute
            ? role == UserRole.bursar
            // Registrar section: the Registrar, plus the Principal and
            // Deputy Principal while the academic screens have no separate
            // Principal view yet (Phase 2).
            : role == UserRole.registrar || role.isPrincipalLevel;

    // A signed-in staff member opening another role's section goes
    // home rather than to the login screen.
    if (!allowed) return _staffHome(role);

    // The timetable editor is Registrar-only. The Principal views.
    final editorPrefix = '${AppRoutes.registrarTimetables}/';
    if (path.startsWith(editorPrefix) && role != UserRole.registrar) {
      return AppRoutes.timetableView(path.substring(editorPrefix.length));
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Custom-position staff home (Askari, Accountant, ...)
  // ---------------------------------------------------------------
  if (isStaffHomeRoute) {
    if (auth.isResolving) return null;
    if (!auth.isUsableStaffSession) return AppRoutes.staffLogin;
    final role = auth.resolvedRole!;
    if (role != UserRole.staffMember) return _staffHome(role);
    return null;
  }

  // ---------------------------------------------------------------
  // TUTOR routes
  // ---------------------------------------------------------------
  if (isTutorRoute) {
    // Public routes (login, register) must stay reachable for
    // unauthenticated users, but redirect authenticated Tutors away so
    // they don't get stuck on the login screen after signing in.
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
    if (isStudentPublicRoute) {
      // The student number screen must stay reachable without a session, but
      // a student whose NSIN has been found must never be left on the
      // form: StudentSearchScreen shows "Loading your account..." in
      // that state and relies on this redirect to move on. Without it
      // the spinner never ends.
      if (student.isRestoring) return null;
      if (student.isUsableSession) return AppRoutes.studentDashboard;
      if (student.currentStudent != null) {
        // Found, but suspended or terminated: not usable, so explain why.
        return AppRoutes.studentAccountInactive;
      }
      return null;
    }
    if (path == AppRoutes.studentAccountInactive) return null;
    if (path == AppRoutes.studentSettings) {
      // Settings must stay reachable even for an inactive session. This
      // is deliberate: it's where clearSession() lives (per the
      // borrowed-phone design), and a student whose session somehow
      // became unusable still needs a way to clear it and start over.
      return null;
    }

    // Still restoring a persisted session from shared_preferences on
    // app startup: don't redirect yet, or it would flash to
    // studentSearch before a valid persisted session finishes loading.
    if (student.isRestoring) return null;

    if (!student.isUsableSession) {
      // Covers both "never searched" and "found but suspended/
      // terminated-course": neither has a usable session to proceed with.
      return AppRoutes.studentSearch;
    }

    return null;
  }

  // ---------------------------------------------------------------
  // PUBLIC space: readable by anyone, signed in or not. Only posting and
  // reviewing need a session; the Firestore rules enforce the same.
  // ---------------------------------------------------------------
  if (path.startsWith('/public')) {
    if (path == AppRoutes.publicNew) {
      if (auth.isResolving) return null;
      // Staff in a custom position can read the Public Space but not post.
      final staffCanPost =
          auth.isUsableStaffSession && auth.resolvedRole!.canPublishPublicly;
      if (!staffCanPost && !auth.isUsableTutorSession) {
        return AppRoutes.publicHome;
      }
      return null;
    }
    if (path == AppRoutes.publicReview) {
      if (auth.isResolving) return null;
      final role = auth.resolvedRole;
      final canReview =
          auth.isUsableStaffSession && role != null && role.canModeratePublic;
      if (!canReview) return AppRoutes.publicHome;
      return null;
    }
    return null;
  }

  return null; // unrecognized path: let GoRouter's own 404 handling apply
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
