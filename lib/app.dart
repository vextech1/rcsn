import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/student_provider.dart';
import 'providers/structure_provider.dart';
import 'providers/tutor_provider.dart';
import 'providers/content_provider.dart';

/// The app itself — MultiProvider wiring every provider batch built so
/// far, plus MaterialApp.router. Split out of main.dart so main.dart
/// stays a pure entry point and this widget is what you'd swap in for
/// widget-testing the app without going through Firebase init at all.
class RcsnApp extends StatelessWidget {
  const RcsnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // AuthProvider and StudentProvider are the two the router's
        // `refreshListenable` and `redirect` guard read directly, so
        // they're created here rather than lower in the tree.
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => StructureProvider()),
        ChangeNotifierProvider(create: (_) => TutorProvider()),
        ChangeNotifierProvider(create: (_) => ContentProvider()),
      ],
      child: Builder(
        builder: (context) {
          // Built once per (authProvider, studentProvider) identity —
          // it's `refreshListenable` that reacts to their changes, not
          // this Builder re-running buildAppRouter on every notify.
          final router = buildAppRouter(
            authProvider: context.read<AuthProvider>(),
            studentProvider: context.read<StudentProvider>(),
          );

          return MaterialApp.router(
            title: 'RCSN Mobile App',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // Explicit, not left to default — follows the phone's
            // system light/dark setting live, including if the user
            // changes it while the app is already open (Flutter re-
            // resolves ThemeMode.system reactively, no restart needed).
            themeMode: ThemeMode.system,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
