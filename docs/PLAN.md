# RCSN Mobile App: Restructure and Hardening Plan

Status: **draft**, 2026-11-25.
Based on a static read of commit `957975e`. The code has not been compiled or run, and the deployed Firebase rules have not been inspected. References to "Section 2.x" mean the project document, which is not in this repo and will need updating to match this plan.

---

## 1. Findings in the current code

| # | Area | Problem | Severity |
|---|------|---------|----------|
| 1 | Admin | `admins` create rule only checks that the caller's *own* doc does not exist, which is true for every new user. "Exactly one admin" is enforced only in client code, so any signed-in user can write `/admins/{theirUid}` and pass `isAdmin()`. | Critical |
| 2 | Admin | `RoleSelectScreen` calls `adminExists()` before sign-in, but the `admins` read rule requires auth. The Admin button fails as committed. | High |
| 3 | Student | Students are not signed in to Firebase Auth, but `subjects`, `content_items` and `content_types` require `request.auth != null`. The student dashboard and subject screens hit permission-denied. | High |
| 4 | Student | `student_devices` has no rule (default deny). FCM tokens never get stored, so push notifications never fire. | High |
| 5 | Student | `students` is `read: if true` and the NSIN is the only credential. Anyone with the public API key can list every NSIN. | High |
| 6 | Student | `AuthProvider` signs out any user with no admin or tutor record, so a Firebase-authenticated student would be signed out immediately. | Blocker for the fix |
| 7 | Tutor | Self-terminate rule does not restrict which fields change. Tutors can rewrite any field of their own content items (including `subjectId`). `tutors` and `tutor_assignments` are readable by any signed-in user. | Medium |
| 8 | Tutor | Video compression runs with `includeAudio: false`, which strips the audio track from lecture videos. | Medium |
| 9 | Infra | No `storage.rules`, `firestore.indexes.json` or `.firebaserc`. The `content_items` list queries need a composite index. | Medium |
| 10 | Student | Offline support is partial: files re-download on every tap, local files are saved by `fileName` alone (collisions), and `sqflite`, `connectivity_plus` and `cached_network_image` are declared but unused. | Low |
| 11 | Housekeeping | Default counter widget test fails. Stale comments ("rules not yet written", "FCM registration not yet built"). Duplicate `com/example/rcsn/MainActivity.kt`. Release builds signed with debug keys. `dev` and `prod` flavor folders are empty. `tutorNotAssigned` is a dead stub route. Cloud Function targets Node 18. | Low |

---

## 2. Target role model

The single Admin is replaced by three staff roles, plus Tutor and Student.

| Role | Who | Sign-in |
|------|-----|---------|
| Principal | School principal | Email and password (staff login) |
| Registrar | Academic registrar / DOS | Email and password (staff login) |
| Bursar | Bursar | Email and password (staff login) |
| Tutor | Teaching staff | Email and password, self-registers (tutor login) |
| Student | Admitted students | NSIN only (no password) |

### Design

- **One `staff` collection.** Doc ID = Firebase Auth uid. Fields: `name`, `email`, `role` (`principal | registrar | bursar`), `status`, `createdAt`, `createdBy`.
- **Staff accounts are created server-side.** A callable Cloud Function `createStaff` (Principal only) creates the Auth user, writes the `staff` doc, sets a `role` custom claim and sends a password-reset email. Creating an Auth user from the client signs the creator out, so this cannot be done in-app.
- **Rules check status live.** The custom claim is used for routing and cheap checks. Rules also read the `staff` doc, so suspending a staff member takes effect immediately.
- **No in-app first-run setup.** A one-time bootstrap script (Admin SDK, run locally) creates the Principal. There is no public creation path, which closes the takeover class of bug.
- **Role select:** Staff, Tutor, Student. The staff login routes to the right dashboard by role.
- **`UserRole` enum:** `principal, registrar, bursar, tutor, student`. Staff roles share the `staff` collection.
- **Routes:** `/admin/*` is replaced by `/staff/login`, `/principal/*`, `/registrar/*`, `/bursar/*`.

### Draft permission matrix

| Capability | Principal | Registrar | Bursar | Tutor | Student |
|---|---|---|---|---|---|
| Create or suspend staff | yes | no | no | no | no |
| Academic structure, content types | view | yes | no | no | no |
| Assign tutors to subjects | view | yes | no | no | no |
| Suspend or terminate tutors | yes | yes | no | self only | no |
| Admit students, change academic status | yes | yes | no | no | no |
| Fee records and payments | view | no | yes | no | own, view |
| Archive or delete any content | view | yes | no | own uploads | no |
| Upload content | no | no | no | assigned subjects | no |
| Read content | all | all | no | assigned subjects | own track |

---

## 3. Phases (top-down)

### Phase 0: Hotfix and groundwork

- [ ] Check the `admins` collection and the Auth users list in the Firebase console for entries you do not recognise.
- [ ] Check which Firestore and Storage rules are actually deployed.
- [ ] Deploy `allow create: if false` on `admins` (assumes the existing admin account already exists; verify first). This closes finding 1 without waiting for the restructure.
- [ ] Restrict the Android API key to the package name and SHA-1 in Google Cloud.
- [ ] Decide whether the GitHub repo should be private (it is currently public and contains `firestore.rules`).
- [ ] Add `.firebaserc` and `firestore.indexes.json` (`content_items`: `subjectId` asc, `isArchived` asc, `uploadedAt` desc).
- [ ] Set up the Firebase Emulator Suite and a rules test suite. Every rule change is tested as: signed-out, student, active tutor, suspended tutor, unassigned tutor, each staff role.

### Phase 1: Principal and staff foundation

- [ ] `staff` collection, rules and `isStaff(role)` helpers.
- [ ] Callable `createStaff` (Principal only) and `setStaffStatus`.
- [ ] Bootstrap script that creates the Principal.
- [ ] Migrate the existing admin account into a Principal `staff` record, then retire `admins`.
- [ ] Public `app_config/setup` flag if any pre-login "is the system set up" check is still needed.
- [ ] Split `UserRole`; rewrite `AuthProvider` role resolution to read `staff`; update the router guard.
- [ ] Staff login screen with role-based redirect.
- [ ] Principal dashboard with staff management (create, suspend, reactivate).

### Phase 2: Registrar

- [ ] Move the structure, content-type, tutor-management and student-admission screens under `/registrar/*`.
- [ ] Rules: Registrar writes structure, assignments, student records and academic status. Principal gets view plus status override.
- [ ] Tutor suspend/terminate available to Registrar and Principal.

### Phase 3: Bursar (new module)

- [ ] Collections: `student_fees/{studentId}` (balance summary) and `fee_payments/{id}` (amount, date, method, receipt number, `recordedBy`).
- [ ] A Cloud Function trigger creates the `student_fees` stub on admission, denormalising name, NSIN and track. This keeps the Bursar off the `students` collection.
- [ ] Rules: Bursar writes; Principal reads; Registrar has no access; a student reads only their own summary.
- [ ] Bursar dashboard: student list, record payment, balance view.
- [ ] Student fee screen (read-only).
- [ ] No payment gateway at this stage.

### Phase 4: Tutor

- [ ] `tutors` readable by self or staff only. Create restricted to the expected fields. Self-terminate limited to `status` via `affectedKeys().hasOnly(['status'])`.
- [ ] `tutor_assignments` readable by the tutor concerned or staff.
- [ ] `content_items`: readable by staff or an assigned active tutor; tutor updates limited to `isArchived` and `description`; create requires `storagePath` starting `subjects/{subjectId}/` and an existing content type.
- [ ] New `storage.rules`: writes and deletes only for an active assigned tutor on `subjects/{id}/content/**`, up to 100MB, allowed types only.
- [ ] Set `includeAudio: true` in video compression.
- [ ] Connectivity check before uploads.
- [ ] Unique local download path per item (shared with Phase 5).

### Phase 5: Student

- [ ] Callable `studentLogin(nsin)`: normalise, look up with the Admin SDK, reject inactive students, return a custom token carrying only `role: student` and the student id.
- [ ] App Check (Play Integrity) and rate limiting on `studentLogin`, since NSINs are guessable (month, year, course code, sequence).
- [ ] Lock down `students`: readable by staff, or by the student's own record only.
- [ ] Student read rules for `subjects`, `content_items`, `content_types` and Storage: the student's live record must be active and the subject must be in their track.
- [ ] `student_devices`: writable only by that student, only `tokens` and `updatedAt`.
- [ ] App: `StudentProvider.searchByNsin` calls the function, then `signInWithCustomToken`; session restore uses the Firebase session; `clearSession` signs out.
- [ ] `AuthProvider` skips role resolution for the student role. Signing in as another role on a shared phone signs the current session out first.
- [ ] Offline: deterministic local path `content/{itemId}/{fileName}`; open if present, otherwise download. Implement or remove the unused `sqflite` and `cached_network_image`.
- [ ] `onContentUploaded` function: current Node runtime, multicast sends, prune dead tokens.

### Wrap-up

- [ ] Replace the default widget test. Add tests for `NsinValidator`, track definitions, router guards and the rules suite.
- [ ] Remove stale comments and the duplicate `MainActivity`.
- [ ] Add a release signing config.
- [ ] Decide whether to keep the `dev` and `prod` flavor folders.
- [ ] Remove the dead `tutorNotAssigned` route.

---

## 4. Rollout

- Phase 0's rule change deploys immediately on its own.
- Each phase is built on its own branch and tested in the emulator before merging.
- Rules, functions, indexes and the matching app build deploy together. The Phase 5 rules break the current student build, which is acceptable at v0.1.0 (pre-release).
- Cloud Functions need the Blaze plan.

## 5. Assumptions (change any of these)

- One Principal. Registrar and Bursar can each have several accounts (for example a deputy).
- The Bursar sees a student's name, NSIN and track, and nothing else academic.
- Unpaid fees do not block content access. Fee data stays separate from the academic side.
- Registrar and Principal both hold DOS-level authority over tutors and students.
- Student login stays NSIN-only, hardened with App Check and rate limiting. A second factor such as date of birth would be stronger but changes Section 2.3 of the project document.
- Students can read any subject in their own track (so earlier-year revision material works). The dashboard still shows only their current year and semester.
- Tutors still self-register as active, with subject assignment as the gate.

## 6. Out of scope for now

- Payment gateway or mobile-money integration.
- iOS build (only the Android platform folder exists).
- Push notifications for fee events.
