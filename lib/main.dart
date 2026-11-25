import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'firebase_options.dart';

/// App entry point — deliberately minimal. Everything about WHAT the app
/// is (providers, theme, router) lives in [RcsnApp] in app.dart; this
/// file only handles WHETHER the platform is ready to run it
/// (Flutter binding, Firebase).
///
/// Firebase initialization failure is caught and is non-fatal: the app
/// launches regardless so UI-only screens (Welcome, RoleSelect, etc.)
/// remain usable. Anything that actually reads or writes Firestore will
/// fail loudly at the point of use.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase.initializeApp() failed — app will run without '
        'Firebase services: $e');
  }

  runApp(const RcsnApp());
}
