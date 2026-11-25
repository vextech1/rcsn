'use strict';

// Run with: firebase emulators:exec --only firestore --project demo-rcsn \
//   "npm --prefix rules-tests test"
// (CI does this in the `rules` job.)

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
} = require('firebase/firestore');

let env;

const subject = {
  name: 'Anatomy',
  programType: 'nursing',
  year: 1,
  semester: 1,
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rcsn',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const staff = (name, role, status = 'active') => ({
      name,
      email: `${name.toLowerCase()}@example.com`,
      role,
      status,
    });
    await setDoc(doc(db, 'staff/principal1'), staff('Principal', 'principal'));
    await setDoc(doc(db, 'staff/registrar1'), staff('Registrar', 'registrar'));
    await setDoc(doc(db, 'staff/registrar2'), staff('Suspended', 'registrar', 'suspended'));
    await setDoc(doc(db, 'staff/bursar1'), staff('Bursar', 'bursar'));
    await setDoc(doc(db, 'tutors/tutor1'), { name: 'T', email: 't@example.com', status: 'active' });
    await setDoc(doc(db, 'tutors/tutor2'), { name: 'S', email: 's@example.com', status: 'suspended' });
    await setDoc(doc(db, 'subjects/s1'), subject);
    await setDoc(doc(db, 'students/stu1'), { nsin: 'X', name: 'Student', status: 'active' });
    await setDoc(doc(db, 'admins/legacy'), { name: 'Old', email: 'old@example.com' });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('staff collection', () => {
  it('signed-out users cannot read or list staff', async () => {
    await assertFails(getDoc(doc(anon(), 'staff/principal1')));
    await assertFails(getDocs(collection(anon(), 'staff')));
  });

  it('a staff member can read their own record', async () => {
    await assertSucceeds(getDoc(doc(as('registrar1'), 'staff/registrar1')));
    await assertSucceeds(getDoc(doc(as('bursar1'), 'staff/bursar1')));
  });

  it('a suspended staff member can still read their own record (login explains why)', async () => {
    await assertSucceeds(getDoc(doc(as('registrar2'), 'staff/registrar2')));
  });

  it('registrar and bursar cannot read another staff record or list staff', async () => {
    await assertFails(getDoc(doc(as('registrar1'), 'staff/principal1')));
    await assertFails(getDoc(doc(as('bursar1'), 'staff/registrar1')));
    await assertFails(getDocs(collection(as('registrar1'), 'staff')));
  });

  it('a tutor or any other signed-in user cannot read staff', async () => {
    await assertFails(getDoc(doc(as('tutor1'), 'staff/principal1')));
    await assertFails(getDocs(collection(as('tutor1'), 'staff')));
  });

  it('the principal can read any record and list staff', async () => {
    await assertSucceeds(getDoc(doc(as('principal1'), 'staff/bursar1')));
    await assertSucceeds(getDocs(collection(as('principal1'), 'staff')));
  });

  it('nobody can write staff from the client, including the principal', async () => {
    await assertFails(setDoc(doc(as('principal1'), 'staff/new1'), { name: 'N', role: 'bursar', status: 'active' }));
    await assertFails(updateDoc(doc(as('principal1'), 'staff/bursar1'), { status: 'suspended' }));
    await assertFails(deleteDoc(doc(as('principal1'), 'staff/bursar1')));
  });

  it('a new user cannot make themselves staff (the old admin-takeover bug)', async () => {
    await assertFails(setDoc(doc(as('attacker'), 'staff/attacker'), { name: 'A', email: 'a@example.com', role: 'principal', status: 'active' }));
    await assertFails(updateDoc(doc(as('registrar1'), 'staff/registrar1'), { role: 'principal' }));
  });
});

describe('legacy admins collection is retired', () => {
  it('cannot be read or written by anyone', async () => {
    await assertFails(getDoc(doc(as('principal1'), 'admins/legacy')));
    await assertFails(getDoc(doc(anon(), 'admins/legacy')));
    await assertFails(setDoc(doc(as('attacker'), 'admins/attacker'), { name: 'A', email: 'a@example.com' }));
    await assertFails(setDoc(doc(as('principal1'), 'admins/principal1'), { name: 'P', email: 'p@example.com' }));
  });
});

describe('academic structure writes (transitional: principal or registrar)', () => {
  it('principal and registrar can create a subject', async () => {
    await assertSucceeds(setDoc(doc(as('principal1'), 'subjects/s2'), subject));
    await assertSucceeds(setDoc(doc(as('registrar1'), 'subjects/s3'), subject));
  });

  it('bursar, suspended staff, tutors and signed-out users cannot', async () => {
    await assertFails(setDoc(doc(as('bursar1'), 'subjects/s4'), subject));
    await assertFails(setDoc(doc(as('registrar2'), 'subjects/s5'), subject));
    await assertFails(setDoc(doc(as('tutor1'), 'subjects/s6'), subject));
    await assertFails(setDoc(doc(anon(), 'subjects/s7'), subject));
  });

  it('registrar can update a student record, bursar cannot', async () => {
    await assertSucceeds(updateDoc(doc(as('registrar1'), 'students/stu1'), { status: 'suspended' }));
    await assertFails(updateDoc(doc(as('bursar1'), 'students/stu1'), { status: 'suspended' }));
  });

  it('a suspended tutor cannot suspend or edit other tutors', async () => {
    await assertFails(updateDoc(doc(as('tutor2'), 'tutors/tutor1'), { status: 'suspended' }));
    await assertFails(updateDoc(doc(as('tutor1'), 'tutors/tutor2'), { status: 'active' }));
  });
});
