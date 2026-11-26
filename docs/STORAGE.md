# File storage: Cloudflare R2

Files are kept in the private R2 bucket `school-management-software`. The app
never talks to R2 directly: it calls the Worker in `worker/`, which checks who
is asking. Firebase Auth and Firestore stay on the Spark plan. Firebase Storage
is no longer used.

## Setup (can be done from a phone)

1. **workers.dev subdomain.** In the Cloudflare dashboard open *Workers & Pages*
   and choose a subdomain if you are asked to.
2. **API token.** *My Profile > API Tokens > Create Token*, template
   *Edit Cloudflare Workers*, limited to your account.
3. **GitHub secrets.** Repository *Settings > Secrets and variables > Actions >
   Secrets*: add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (the long
   id in the dashboard address).
4. **Deploy.** *Actions > Deploy storage Worker > Run workflow*. The log ends
   with the address, `https://rcsn-files.<subdomain>.workers.dev`.
5. **Tell the app.** Same settings page, *Variables* tab: add `STORAGE_URL` with
   that address. Then run *Actions > CI* and install the new APK.

Keep the bucket's *Public Development URL* disabled and add no custom domain to
the bucket, or files become readable without any check.

## Who can do what

| Caller | Upload | Download | Delete |
|---|---|---|---|
| Principal, Registrar (active) | yes | yes | any file |
| Tutor (active, assigned to the subject) | yes | yes | own uploads |
| Student (active, NSIN, same programme) | no | yes | no |
| Bursar, anyone else | no | no | no |

Allowed: PDF, Word, Excel and images (jpg, jpeg, png, heic), up to 95 MB.
Existing files are never overwritten. The lists live in
`worker/src/index.js` and `lib/core/constants/upload_rules.dart`; change both.

## Website

Add the site's address to `ALLOWED_ORIGINS` in `worker/wrangler.toml`. The site
must sign users in with the `school-msa` Firebase project.

    PUT | GET | DELETE  /files/subjects/{subjectId}/content/{fileName}
    Authorization: Bearer <Firebase ID token>
    (students, GET only)  X-Student-NSIN: <nsin>

URL-encode the file name. Choose a unique name for each upload. A download
needs the header, so use `fetch` and save the blob; a plain link will not work.

## Limits and known gaps

- **Student access is weak.** An NSIN is the only proof and NSINs are
  sequential, so someone could guess one. Fine for testing with mock data;
  needs real student sessions before launch.
- Free allowances (check current figures): R2 10 GB stored; Workers 100,000
  requests a day. R2 usage beyond its allowance is billed.
- Each file request also uses one to three Firestore reads.
