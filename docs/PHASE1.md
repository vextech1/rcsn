# Phase 1: deploy and bootstrap

Phase 1 replaces the single Admin with `staff` (Principal, Registrar, Bursar).
**Nothing here is deployed by merging.** Follow this order, because the new rules
lock the old `admins` collection.

1. **Deploy the functions.** `cd functions && npm install`, then
   `firebase deploy --only functions`. Needs the Blaze plan. Runtime is Node 22.
2. **Create the Principal** (local, Admin SDK). Authenticate first with
   `gcloud auth application-default login`, then from `functions/`:
   - Keep your current admin login: `npm run bootstrap -- --from-admin`
     (same uid, so the same email and password keep working), or
   - Fresh account: `npm run bootstrap -- --name "Full Name" --email you@example.com`
     (prints a one-time link to set the password).

   The script refuses to run if a Principal already exists, and seeds the default
   content types if there are none.
3. **Deploy the rules and indexes.** `firebase deploy --only firestore:rules,firestore:indexes`.
4. **Install the new app build** and sign in through Role Select, then Staff.
   The Principal dashboard has a Staff tile to add a Registrar or Bursar. They get
   an email to set their own password.

If the rules go out before step 2, the data is not lost; the app simply can't
resolve a role until the Principal record exists. Running the script fixes it.

## Known limits in this phase

- Registrar and Principal share the academic screens (the old Admin screens,
  now under `/registrar/*`). Phase 2 rebuilds them and narrows the rules.
- The Bursar dashboard is a placeholder until Phase 3.
- Student and tutor behaviour is unchanged, including the known student-side
  permission problems (findings 3 to 6 in `PLAN.md`), which Phase 5 fixes.
