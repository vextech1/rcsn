#!/usr/bin/env node
'use strict';

// Seeds MOCK accounts and data for testing. Works on the free Spark plan
// (Admin SDK only). Idempotent: safe to run again, it updates in place.
//
//   MOCK_PASSWORD=... node seed-mock-data.js --project school-msa
//   node seed-mock-data.js --project school-msa --cleanup
//
// Every mock login uses the password in MOCK_PASSWORD (never printed, never
// stored in the repo). Mock records are recognisable without any marker field
// (the student model rejects unknown fields): emails end in @mock.rcsn.test,
// document ids start with "mock-", and student NSINs use the course code MCK.
// --cleanup removes exactly those.

const admin = require('firebase-admin');

const DOMAIN = 'mock.rcsn.test';
const em = (local) => `${local}@${DOMAIN}`;

const STAFF = [
  { name: 'Dr. Grace Namuli', email: em('principal'), role: 'principal' },
  { name: 'Peter Okello', email: em('registrar'), role: 'registrar' },
  { name: 'Sarah Nakato', email: em('bursar'), role: 'bursar' },
];

const TUTORS = [
  { name: 'James Mugisha', email: em('tutor1'), status: 'active' },
  { name: 'Agnes Kyomuhendo', email: em('tutor2'), status: 'active' },
  { name: 'Brian Ssemakula', email: em('tutor3'), status: 'suspended' },
];

const SUBJECTS = [
  { id: 'mock-anatomy', name: 'Anatomy and Physiology', programType: 'certificateNursing', year: 1, semester: 1 },
  { id: 'mock-fundamentals', name: 'Fundamentals of Nursing', programType: 'certificateNursing', year: 1, semester: 1 },
  { id: 'mock-midwifery-1', name: 'Midwifery Practice I', programType: 'certificateMidwifery', year: 1, semester: 1 },
];

// tutor email -> subject ids
const ASSIGNMENTS = [
  [em('tutor1'), 'mock-anatomy'],
  [em('tutor2'), 'mock-fundamentals'],
];

const STUDENTS = [
  { id: 'mock-student-1', nsin: 'JAN26/U028/MCK/001', name: 'Mary Achieng', programType: 'certificateNursing', year: 1, semester: 1, status: 'active' },
  { id: 'mock-student-2', nsin: 'JAN26/U028/MCK/002', name: 'John Opio', programType: 'certificateNursing', year: 1, semester: 1, status: 'active' },
  { id: 'mock-student-3', nsin: 'JAN26/U028/MCK/003', name: 'Esther Namugga', programType: 'certificateMidwifery', year: 1, semester: 1, status: 'active' },
  { id: 'mock-student-4', nsin: 'JAN26/U028/MCK/004', name: 'David Lubega', programType: 'diplomaDirectNursing', year: 2, semester: 1, status: 'active' },
  { id: 'mock-student-5', nsin: 'JAN26/U028/MCK/005', name: 'Ruth Atim', programType: 'certificateNursing', year: 1, semester: 1, status: 'suspended' },
];

const DEFAULT_CONTENT_TYPES = ['Timetable', 'Revision Notes', 'Past Papers', 'Announcements'];

const arg = (name) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : undefined;
};
const flag = (name) => process.argv.includes(`--${name}`);

function fail(message) {
  console.error(`\nERROR: ${message}\n`);
  process.exit(1);
}

async function ensureUser(auth, { name, email }, password) {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, { password, displayName: name, disabled: false });
    return { uid: existing.uid, created: false };
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const user = await auth.createUser({ email, password, displayName: name, emailVerified: true });
    return { uid: user.uid, created: true };
  }
}

async function seed(db, auth, password) {
  const ts = admin.firestore.Timestamp.now();

  // Staff. Exactly one Principal may exist.
  const existingPrincipal = await db.collection('staff').where('role', '==', 'principal').limit(1).get();
  const mockPrincipalEmail = em('principal');
  const realPrincipalExists =
    !existingPrincipal.empty && existingPrincipal.docs[0].get('email') !== mockPrincipalEmail;

  for (const s of STAFF) {
    if (s.role === 'principal' && realPrincipalExists) {
      console.log(`SKIP  ${s.email}: a real Principal already exists (${existingPrincipal.docs[0].get('email')}).`);
      continue;
    }
    const { uid, created } = await ensureUser(auth, s, password);
    await db.collection('staff').doc(uid).set({
      name: s.name, email: s.email, role: s.role, status: 'active',
      createdAt: ts, createdBy: 'seed',
    });
    console.log(`${created ? 'NEW ' : 'OK  '}  staff   ${s.role.padEnd(9)} ${s.email}`);
  }

  // Tutors
  const tutorIds = {};
  for (const t of TUTORS) {
    const { uid, created } = await ensureUser(auth, t, password);
    tutorIds[t.email] = uid;
    await db.collection('tutors').doc(uid).set({
      name: t.name, email: t.email, status: t.status, registeredAt: ts,
    });
    console.log(`${created ? 'NEW ' : 'OK  '}  tutor   ${t.status.padEnd(9)} ${t.email}`);
  }

  // Subjects and assignments
  for (const sub of SUBJECTS) {
    const { id, ...fields } = sub;
    await db.collection('subjects').doc(id).set({ ...fields, createdAt: ts });
  }
  console.log(`OK    ${SUBJECTS.length} subjects`);
  for (const [email, subjectId] of ASSIGNMENTS) {
    const tutorId = tutorIds[email];
    await db.collection('tutor_assignments').doc(`${tutorId}_${subjectId}`).set({
      tutorId, subjectId, assignedAt: ts,
    });
  }
  console.log(`OK    ${ASSIGNMENTS.length} tutor assignments`);

  // Students (no auth accounts: NSIN-only access). No extra fields allowed.
  for (const st of STUDENTS) {
    const { id, ...fields } = st;
    await db.collection('students').doc(id).set({ ...fields, admittedAt: ts });
  }
  console.log(`OK    ${STUDENTS.length} students (NSINs ${STUDENTS[0].nsin} to ${STUDENTS[STUDENTS.length - 1].nsin}; the last is suspended)`);

  // Content types, only if none exist
  const types = await db.collection('content_types').limit(1).get();
  if (types.empty) {
    const batch = db.batch();
    for (const name of DEFAULT_CONTENT_TYPES) {
      batch.set(db.collection('content_types').doc(), { name, createdAt: ts });
    }
    await batch.commit();
    console.log(`OK    seeded ${DEFAULT_CONTENT_TYPES.length} content types`);
  }
}

async function cleanup(db, auth) {
  const emails = [...STAFF.map((s) => s.email), ...TUTORS.map((t) => t.email)];
  for (const email of emails) {
    try {
      const user = await auth.getUserByEmail(email);
      const staffDoc = await db.collection('staff').doc(user.uid).get();
      if (staffDoc.exists && staffDoc.get('email') === email) await staffDoc.ref.delete();
      const tutorDoc = await db.collection('tutors').doc(user.uid).get();
      if (tutorDoc.exists && tutorDoc.get('email') === email) await tutorDoc.ref.delete();
      const assigns = await db.collection('tutor_assignments').where('tutorId', '==', user.uid).get();
      for (const a of assigns.docs) await a.ref.delete();
      await auth.deleteUser(user.uid);
      console.log(`DEL   ${email}`);
    } catch (e) {
      if (e.code === 'auth/user-not-found') console.log(`--    ${email} (not present)`);
      else throw e;
    }
  }
  for (const sub of SUBJECTS) await db.collection('subjects').doc(sub.id).delete();
  for (const st of STUDENTS) await db.collection('students').doc(st.id).delete();
  console.log('DEL   mock subjects and students');
}

async function main() {
  const projectId = arg('project') || process.env.GCLOUD_PROJECT || 'school-msa';
  admin.initializeApp({ projectId });
  const db = admin.firestore();
  const auth = admin.auth();

  if (flag('cleanup')) {
    await cleanup(db, auth);
  } else {
    const password = process.env.MOCK_PASSWORD;
    if (!password || password.length < 10) fail('Set MOCK_PASSWORD (at least 10 characters).');
    await seed(db, auth, password);
  }
  console.log('\nDone.');
}

main().catch((e) => {
  console.error(`\nFAILED: ${e.code || ''} ${e.message || e}`);
  process.exit(1);
});
