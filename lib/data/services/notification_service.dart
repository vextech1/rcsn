import 'package:firebase_messaging/firebase_messaging.dart';

/// Thin wrapper around Firebase Cloud Messaging.
///
/// Per Section 2.3, a Student receives a push notification when a tutor
/// uploads new content to one of their subjects. This service handles the
/// device-side half of that (requesting permission, registering the
/// device token, listening for incoming messages) — it does NOT decide
/// *who* receives a given notification. Figuring out "which students are
/// scoped to this subject's track/year/semester" requires querying
/// StudentRecord (see student_record.dart) against the Subject being
/// uploaded into, which is a repository-level join, not something this
/// thin service layer should know how to do. In production, the actual
/// send-to-audience step typically happens server-side (a Cloud Function
/// triggered on new ContentItem creation) rather than from the client at
/// all — this service's send-side method is a placeholder for that until
/// the Cloud Functions piece is built, not the final production path.
class NotificationService {
  final FirebaseMessaging _messaging;

  NotificationService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  /// Requests notification permission — required on iOS before any
  /// notification will actually display, and good practice to request
  /// explicitly on Android too rather than assume it's granted.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// The device's FCM token — this is what gets stored against a
  /// Student's or Tutor's account record so a server-side function knows
  /// where to send a notification for that specific device.
  Future<String?> getToken() => _messaging.getToken();

  /// Called when the token refreshes (FCM rotates tokens periodically) —
  /// the caller (repository layer) should re-save this against the
  /// current user's account record whenever it fires, or notifications
  /// will silently stop reaching a device using a stale token.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// Foreground message stream — fires when a notification arrives while
  /// the app is open. Background/terminated-state handling requires a
  /// separate top-level background handler registered in main.dart, not
  /// through this instance method (a Flutter/FCM platform requirement,
  /// not a design choice made here).
  Stream<RemoteMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage;

  /// Fires when the user taps a notification and the app opens/resumes
  /// as a result — used to navigate directly to the relevant subject.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;
}
