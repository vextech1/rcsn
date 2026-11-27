# Phase 1: first-run setup and deploy (Spark plan)

The project runs on the free **Spark** plan, so there are **no Cloud Functions**.
Staff management is done by the Principal's app and enforced by Firestore rules.
Merging does not deploy anything. Follow this order, because the new rules lock
the old `admins` collection.

1. **Rules deploy first** (step 2 below). The setup screen needs them.
2. **Rules deploy automatically.** `.github/workflows/deploy-firebase.yml` deploys the
   Firestore rules, indexes and Storage rules to `school-msa` whenever CI passes on `main`
   (it needs the `FIREBASE_SERVICE_ACCOUNT` secret). Manual fallback:
   `firebase deploy --only firestore:rules,firestore:indexes --project school-msa`
   (never a bare `firebase deploy`).
3. **Install the app and register the Principal from it.** On a brand-new school the
   app shows only a *Register as Principal* screen (name, email, password). The first
   person to register becomes the Principal and lands on the Principal dashboard.
   Nobody else can register (tutor registration is refused too) until that has
   happened, and it can only happen once. **Register before you share the APK with
   anyone**: whoever opens the app first claims the Principal role.
4. **Add staff.** The Principal dashboard has a Staff tile to add a Registrar or
   Bursar, who each get an email to set their own password. The default content
   types can be added from the Content Types screen.

## How first-run setup is locked

The marker is one document, `system/setup`. The app creates it in the same atomic
batch as the Principal's own `staff/<uid>` record, and `firestore.rules` allow that
pair only while the marker does not exist, only for the caller's own uid, and only as
a clean active `principal` record. After that the marker cannot be edited or deleted
from a client, so a second Principal can never register. Tutor self-registration also
requires the marker. Anyone can read the marker (the app checks it at launch before
anyone signs in).

## How suspension works without Cloud Functions

Suspending sets `status` on the staff record. The rules read it live on every request,
so a suspended person immediately loses access to data, and the app signs them out
the next time it resolves their role. Their Firebase login itself stays enabled
(disabling an Auth user needs the Admin SDK), which is harmless because the login
alone grants nothing.

## Known limits in this phase

- Registrar and Principal share the academic screens (the old Admin screens, now under
  `/registrar/*`). Phase 2 rebuilds them and narrows the rules.
- The Bursar dashboard is a placeholder until Phase 3.
- Student and tutor behaviour is unchanged, including the known student-side permission
  problems (findings 3 to 6 in `PLAN.md`), which Phase 5 fixes.
- Push notifications on new content (`functions/`) are dormant until the Blaze plan.
