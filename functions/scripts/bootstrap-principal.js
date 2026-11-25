#!/usr/bin/env node
'use strict';

// One-time bootstrap for the Principal account. Runs locally with the Admin
// SDK; there is deliberately no in-app or public way to do this.
//
// Credentials: run `gcloud auth application-default login` first, or set
// GOOGLE_APPLICATION_CREDENTIALS to a service-account key for the project.
//
// Fresh Principal:
//   node scripts/bootstrap-principal.js --name "Full Name" --email you@example.com
//
// Migrate the existing single Admin into the Principal record (keeps the
// same Auth uid, so the same email and password keep working):
//   node scripts/bootstrap-principal.js --from-admin [--delete-legacy]
//
// Optional: --project <id> (defaults to rcsn-765ff).
//
// Refuses to run if a Principal already exists. Also seeds the default
// content types if none exist (the old in-app first-run setup did this).

const admin = require('firebase-admin');
const crypto = require('crypto');

const SEEDED_CONTENT_TYPES = [
  'Timetable',
  'Revision Notes',
  'Past Papers',
  'Announcements',
];

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : undefined;
}
const flag = (name) => process.argv.includes(`--${name}`);

function fail(message) {
  console.error(`\nERROR: ${message}\n`);
  process.exit(1);
}

async function main() {
  const projectId = arg('project') || process.env.GCLOUD_PROJECT || 'rcsn-765ff';
  admin.initializeApp({ projectId });
  const db = admin.firestore();
  const auth = admin.auth();

  const existing = await db
    .collection('staff')
    .where('role', '==', 'principal')
    .limit(1)
    .get();
  if (!existing.empty) {
    fail(`A Principal already exists (${existing.docs[0].id}). Nothing to do.`);
  }

  let uid;
  let name;
  let email;
  let createdAuthUser = false;

  if (flag('from-admin')) {
    const legacy = await db.collection('admins').limit(1).get();
    if (legacy.empty) fail('No document found in the legacy `admins` collection.');
    const doc = legacy.docs[0];
    uid = doc.id;
    name = doc.get('name');
    email = doc.get('email');
    if (!name || !email) fail('The legacy admin document is missing name or email.');
    await auth.getUser(uid).catch(() => fail(`No Auth user exists for uid ${uid}.`));
    console.log(`Migrating legacy admin ${email} (${uid}) to Principal.`);
  } else {
    name = (arg('name') || '').trim();
    email = (arg('email') || '').trim().toLowerCase();
    if (name.length < 2) fail('Pass --name "Full Name" (or use --from-admin).');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail('Pass a valid --email.');
    const user = await auth.createUser({
      email,
      displayName: name,
      password: crypto.randomBytes(24).toString('base64url'),
    });
    uid = user.uid;
    createdAuthUser = true;
  }

  try {
    await auth.setCustomUserClaims(uid, { role: 'principal' });
    await db.collection('staff').doc(uid).set({
      name,
      email,
      role: 'principal',
      status: 'active',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'bootstrap',
    });
  } catch (e) {
    if (createdAuthUser) await auth.deleteUser(uid).catch(() => {});
    throw e;
  }
  console.log(`Created staff/${uid} with role principal.`);

  const types = await db.collection('content_types').limit(1).get();
  if (types.empty) {
    const batch = db.batch();
    for (const typeName of SEEDED_CONTENT_TYPES) {
      batch.set(db.collection('content_types').doc(), {
        name: typeName,
        createdAt: admin.firestore.Timestamp.now(),
      });
    }
    await batch.commit();
    console.log(`Seeded ${SEEDED_CONTENT_TYPES.length} default content types.`);
  }

  if (createdAuthUser) {
    const link = await auth.generatePasswordResetLink(email);
    console.log('\nOpen this link once to set the Principal password:\n');
    console.log(link);
  }

  if (flag('from-admin') && flag('delete-legacy')) {
    await db.collection('admins').doc(uid).delete();
    console.log('\nDeleted the legacy admins document.');
  } else if (flag('from-admin')) {
    console.log(
      '\nThe legacy admins document was left in place. The rules already lock it,' +
        '\nso it is harmless; delete it in the console whenever you like.'
    );
  }

  console.log('\nDone.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
