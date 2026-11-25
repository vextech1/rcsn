const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ---------------------------------------------------------------------------
// onContentUploaded
//
// Trigger: a new document is created in the `content_items` collection
// (i.e. a tutor uploads a file into a subject).
//
// Action: queries the `students` collection for every student whose
// academic scope (programType, year, semester) matches the subject the
// content was uploaded into, then sends a push notification to each of
// those students' registered devices.
//
// Device tokens live in a SEPARATE collection — `student_devices` —
// rather than on the `students` document itself. This keeps the
// `students` collection purely academic data (matching StudentRecord's
// own scope-boundary comment in the Flutter code) and avoids the
// _knownFields assert in StudentRecord.fromFirestore. Each student
// document in `student_devices` has a `tokens` array of FCM tokens
// (a student may have the app installed on multiple devices).
//
// FCM TOKEN REGISTRATION (not yet built in the Flutter app):
// When a student successfully looks up their NSIN and enters the app,
// the Flutter code must:
//   1. Call NotificationService.getToken() to get the device's FCM token
//   2. Write it to Firestore:
//        db.collection('student_devices')
//          .doc(studentRecord.id)
//          .set({
//            tokens: admin.firestore.FieldValue.arrayUnion([token])
//          }, { merge: true });
//   3. Listen to NotificationService.onTokenRefresh and repeat step 2
//      whenever the token rotates.
//
// ERROR HANDLING: notification delivery failures (invalid token, device
// offline, etc.) are logged but do NOT cause the function to fail. A
// failed notification should never block the upload itself — the
// ContentItem document is already committed by the time this function
// runs. The worst case is a student doesn't get notified, not that the
// upload silently fails.
//
// COLD START: this function makes up to N+2 Firestore reads (1 subject
// lookup + 1 student query + up to N student_device lookups). For a
// school with hundreds of students in a single track/year/semester,
// consider batching the FCM sends or using a single multicast message
// per 500 tokens. The current implementation sends individual messages
// for simplicity — adequate for the expected scale of a nursing school.
// ---------------------------------------------------------------------------
exports.onContentUploaded = functions.firestore
  .document('content_items/{itemId}')
  .onCreate(async (snap, context) => {
    const contentItem = snap.data();
    const subjectId = contentItem.subjectId;

    if (!subjectId) {
      console.error('onContentUploaded: missing subjectId on content item', snap.id);
      return null;
    }

    // --- 1. Resolve the Subject to get its academic scope ---
    let subjectDoc;
    try {
      subjectDoc = await db.collection('subjects').doc(subjectId).get();
    } catch (err) {
      console.error('onContentUploaded: failed to fetch subject', subjectId, err);
      return null;
    }

    if (!subjectDoc.exists) {
      console.error('onContentUploaded: subject not found', subjectId);
      return null;
    }

    const subject = subjectDoc.data();
    const { programType, year, semester, name: subjectName } = subject;

    if (!programType || year == null || semester == null) {
      console.error(
        'onContentUploaded: subject missing scope fields',
        subjectId,
        { programType, year, semester }
      );
      return null;
    }

    // --- 2. Find all students scoped to this subject ---
    let studentSnapshots;
    try {
      studentSnapshots = await db
        .collection('students')
        .where('programType', '==', programType)
        .where('year', '==', year)
        .where('semester', '==', semester)
        .where('status', '==', 'active') // don't notify suspended/terminated students
        .get();
    } catch (err) {
      console.error('onContentUploaded: failed to query students', err);
      return null;
    }

    if (studentSnapshots.empty) {
      console.log(
        'onContentUploaded: no active students found for scope',
        { programType, year, semester }
      );
      return null;
    }

    const studentCount = studentSnapshots.size;
    console.log(
      `onContentUploaded: found ${studentCount} student(s) for ` +
        `${programType} Y${year} S${semester}`
    );

    // --- 3. Build the notification payload ---
    const contentTypeName = contentItem.description ?? contentItem.fileName;
    const title = `New ${subjectName ?? 'content'} uploaded`;
    const body = contentTypeName
      ? `"${contentTypeName}" has been added to ${subjectName ?? 'your subject'}.`
      : `New content has been added to ${subjectName ?? 'your subject'}.`;

    // data payload: carries enough context for the Flutter app to
    // navigate directly to the relevant subject when the student taps
    // the notification (see NotificationService.onMessageOpenedApp).
    const dataPayload = {
      subjectId: subjectId,
      contentItemId: snap.id,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    };

    // --- 4. Send to each student's registered devices ---
    const sendPromises = [];

    for (const studentDoc of studentSnapshots.docs) {
      const studentId = studentDoc.id;

      // Read the student's device tokens from the separate
      // student_devices collection.
      let deviceDoc;
      try {
        deviceDoc = await db.collection('student_devices').doc(studentId).get();
      } catch (err) {
        console.error(
          `onContentUploaded: failed to fetch device tokens for student ${studentId}`,
          err
        );
        continue;
      }

      if (!deviceDoc.exists) {
        // Student has never opened the app on any device — no token
        // to send to. This is normal for newly admitted students.
        continue;
      }

      const tokens = deviceDoc.data().tokens;
      if (!tokens || !Array.isArray(tokens) || tokens.length === 0) {
        continue;
      }

      // Send one message per token. At scale, use sendMulticast()
      // with up to 500 tokens per call instead.
      for (const token of tokens) {
        sendPromises.push(
          messaging
            .send({
              token: token,
              notification: { title, body },
              data: dataPayload,
              android: {
                priority: 'high',
                notification: {
                  channelId: 'content_uploads',
                  sound: 'default',
                },
              },
              apns: {
                payload: {
                  aps: {
                    sound: 'default',
                    badge: 1,
                  },
                },
              },
            })
            .then(() => {
              console.log(`Notification sent to student ${studentId}`);
            })
            .catch((err) => {
              // Individual send failures (invalid token, device
              // unregistered, etc.) are logged but don't fail the
              // function. The Firebase Admin SDK will return specific
              // error codes like 'messaging/registration-token-not-
              // registered' — in production, you'd want to clean up
              // stale tokens here.
              console.error(
                `Failed to send notification to student ${studentId}`,
                err.code ?? err.message
              );
            })
        );
      }
    }

    if (sendPromises.length === 0) {
      console.log(
        'onContentUploaded: no device tokens to send to — ' +
          'students exist but none have registered devices yet'
      );
      return null;
    }

    // Wait for all sends to settle. Individual failures are caught
    // inside each promise's .catch() above, so Promise.all will never
    // reject here even if some sends fail.
    await Promise.all(sendPromises);

    console.log(
      `onContentUploaded: finished — ${sendPromises.length} notification(s) ` +
        `attempted for ${studentCount} student(s)`
    );

    return null;
  });
