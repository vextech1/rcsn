# Phase 1: bootstrap and deploy (Spark plan)

The project runs on the free **Spark** plan, so there are **no Cloud Functions**.
Staff management is done by the Principal's app and enforced by Firestore rules.
Merging does not deploy anything. Follow this order, because the new rules lock
the old `admins` collection.

1. **Create the Principal record** (pick one):
   - **By hand, no tooling.** In the Firebase console open Firestore, create
     `staff/<your-admin-uid>` (the uid is on the Authentication tab for your existing
     admin user) with string fields `name`, `email`, `role` = `principal`,
     `status` = `active`, and a timestamp `createdAt`. Your existing email and
     password keep working.
   - **Script.** In `tools/`: `npm install`, download a service-account key
     (Project settings, Service accounts, Generate new private key), then
     `GOOGLE_APPLICATION_CREDENTIALS=path/to/key.json node bootstrap-principal.js --from-admin`.
     Or for a fresh account: `--name "Full Name" --email you@example.com`.
     It refuses to run if a Principal already exists, and seeds the default content
     types if there are none. Delete the key afterwards.
2. **Rules deploy automatically.** `.github/workflows/deploy-firebase.yml` deploys the
   Firestore rules, indexes and Storage rules to `school-msa` whenever CI passes on `main`
   (it needs the `FIREBASE_SERVICE_ACCOUNT` secret). Manual fallback:
   `firebase deploy --only firestore:rules,firestore:indexes --project school-msa`
   (never a bare `firebase deploy`).
3. **Install the new app build** and sign in through Role Select, then Staff. The
   Principal dashboard has a Staff tile to add a Registrar or Bursar, who each get an
   email to set their own password.

The rules do not need the Principal to exist first on a fresh project. If they go out before step 1, no data is lost; the app just can't resolve a
role until the Principal record exists.

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
