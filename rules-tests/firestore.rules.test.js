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
  serverTimestamp,
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
    await setDoc(doc(db, 'tutors/tutor3'), { name: 'U', email: 'u@example.com', status: 'active' });
    await setDoc(doc(db, 'tutor_assignments/tutor1_s1'), { tutorId: 'tutor1', subjectId: 's1' });
    await setDoc(doc(db, 'tutor_assignments/tutor2_s1'), { tutorId: 'tutor2', subjectId: 's1' });
    await setDoc(doc(db, 'subjects/s1'), subject);
    await setDoc(doc(db, 'content_types/ct1'), { name: 'Notes' });
    await setDoc(doc(db, 'content_items/existing1'), {
      subjectId: 's1', contentTypeId: 'ct1', fileName: 'a.pdf',
      fileUrl: 'https://example.com/a.pdf', storagePath: 'x/a.pdf',
      isArchived: false, uploadedByTutorId: 'tutor1',
    });
    await setDoc(doc(db, 'students/stu1'), { nsin: 'X', name: 'Student', status: 'active' });
    await setDoc(doc(db, 'admins/legacy'), { name: 'Old', email: 'old@example.com' });
  });
});

const newStaff = (createdBy, role) => ({
  name: 'New Person',
  email: 'new.person@example.com',
  role,
  status: 'active',
  createdAt: serverTimestamp(),
  createdBy,
});

const statusChange = (updatedBy, status) => ({
  status,
  updatedAt: serverTimestamp(),
  updatedBy,
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

  it('nobody can delete staff, including the principal', async () => {
    await assertFails(deleteDoc(doc(as('principal1'), 'staff/bursar1')));
    await assertFails(deleteDoc(doc(as('registrar1'), 'staff/registrar1')));
  });

  it('a new user cannot make themselves staff (the old admin-takeover bug)', async () => {
    await assertFails(setDoc(doc(as('attacker'), 'staff/attacker'), newStaff('attacker', 'principal')));
    await assertFails(setDoc(doc(as('attacker'), 'staff/attacker'), newStaff('attacker', 'registrar')));
    await assertFails(updateDoc(doc(as('registrar1'), 'staff/registrar1'), { role: 'principal' }));
  });

  it('only the principal can create staff, and only registrar or bursar', async () => {
    await assertSucceeds(setDoc(doc(as('principal1'), 'staff/new1'), newStaff('principal1', 'registrar')));
    await assertSucceeds(setDoc(doc(as('principal1'), 'staff/new2'), newStaff('principal1', 'bursar')));
    await assertFails(setDoc(doc(as('principal1'), 'staff/new3'), newStaff('principal1', 'principal')));
    await assertFails(setDoc(doc(as('registrar1'), 'staff/new4'), newStaff('registrar1', 'bursar')));
    await assertFails(setDoc(doc(as('bursar1'), 'staff/new5'), newStaff('bursar1', 'registrar')));
    await assertFails(setDoc(doc(as('tutor1'), 'staff/new6'), newStaff('tutor1', 'registrar')));
    await assertFails(setDoc(doc(anon(), 'staff/new7'), newStaff('principal1', 'registrar')));
  });

  it('a created staff record must be well-formed', async () => {
    const db = as('principal1');
    await assertFails(setDoc(doc(db, 'staff/bad1'), { ...newStaff('principal1', 'registrar'), status: 'suspended' }));
    await assertFails(setDoc(doc(db, 'staff/bad2'), { ...newStaff('principal1', 'registrar'), createdBy: 'someone-else' }));
    await assertFails(setDoc(doc(db, 'staff/bad3'), { ...newStaff('principal1', 'registrar'), extra: true }));
    await assertFails(setDoc(doc(db, 'staff/bad4'), { ...newStaff('principal1', 'registrar'), name: 'X' }));
    await assertFails(setDoc(doc(db, 'staff/bad5'), { ...newStaff('principal1', 'registrar'), email: 'not-an-email' }));
    await assertFails(setDoc(doc(db, 'staff/bad6'), { ...newStaff('principal1', 'registrar'), createdAt: new Date(0) }));
  });

  it('the principal cannot overwrite an existing staff record via create', async () => {
    await assertFails(setDoc(doc(as('principal1'), 'staff/principal1'), newStaff('principal1', 'registrar')));
  });

  it('the principal can suspend and reactivate others', async () => {
    const db = as('principal1');
    await assertSucceeds(updateDoc(doc(db, 'staff/bursar1'), statusChange('principal1', 'suspended')));
    await assertSucceeds(updateDoc(doc(db, 'staff/registrar2'), statusChange('principal1', 'active')));
  });

  it('the principal cannot change anything but status, nor themselves', async () => {
    const db = as('principal1');
    await assertFails(updateDoc(doc(db, 'staff/bursar1'), { ...statusChange('principal1', 'suspended'), role: 'principal' }));
    await assertFails(updateDoc(doc(db, 'staff/bursar1'), { ...statusChange('principal1', 'suspended'), name: 'Renamed' }));
    await assertFails(updateDoc(doc(db, 'staff/bursar1'), statusChange('someone-else', 'suspended')));
    await assertFails(updateDoc(doc(db, 'staff/bursar1'), statusChange('principal1', 'deleted')));
    await assertFails(updateDoc(doc(db, 'staff/principal1'), statusChange('principal1', 'suspended')));
  });

  it('other staff cannot change status, including un-suspending themselves', async () => {
    await assertFails(updateDoc(doc(as('registrar1'), 'staff/bursar1'), statusChange('registrar1', 'suspended')));
    await assertFails(updateDoc(doc(as('registrar2'), 'staff/registrar2'), statusChange('registrar2', 'active')));
    await assertFails(updateDoc(doc(as('bursar1'), 'staff/bursar1'), statusChange('bursar1', 'suspended')));
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

describe('content uploads (assignment check)', () => {
  const item = (tutorId) => ({
    subjectId: 's1',
    contentTypeId: 'ct1',
    fileName: 'notes.pdf',
    fileUrl: 'https://example.com/notes.pdf',
    storagePath: 'subjects/s1/content/notes.pdf',
    isArchived: false,
    uploadedByTutorId: tutorId,
  });

  it('an active tutor assigned to the subject can upload', async () => {
    await assertSucceeds(setDoc(doc(as('tutor1'), 'content_items/c1'), item('tutor1')));
  });

  it('an active tutor NOT assigned to the subject cannot', async () => {
    await assertFails(setDoc(doc(as('tutor3'), 'content_items/c2'), item('tutor3')));
  });

  it('a suspended tutor cannot, even if still assigned', async () => {
    await assertFails(setDoc(doc(as('tutor2'), 'content_items/c3'), item('tutor2')));
  });

  it('a tutor cannot upload on behalf of another tutor', async () => {
    await assertFails(setDoc(doc(as('tutor1'), 'content_items/c4'), item('tutor3')));
  });

  it('a signed-out user cannot upload', async () => {
    await assertFails(setDoc(doc(anon(), 'content_items/c5'), item('tutor1')));
  });
});

describe('student read access (interim public read, no sign-in)', () => {
  it('a signed-out student can read subjects, content types and content items', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'subjects/s1')));
    await assertSucceeds(getDocs(collection(anon(), 'subjects')));
    await assertSucceeds(getDocs(collection(anon(), 'content_types')));
    await assertSucceeds(getDocs(collection(anon(), 'content_items')));
  });

  it('but cannot write any of them', async () => {
    await assertFails(setDoc(doc(anon(), 'subjects/new'), subject));
    await assertFails(updateDoc(doc(anon(), 'subjects/s1'), { name: 'Hacked' }));
    await assertFails(deleteDoc(doc(anon(), 'subjects/s1')));
    await assertFails(setDoc(doc(anon(), 'content_types/new'), { name: 'X' }));
    await assertFails(updateDoc(doc(anon(), 'content_items/existing1'), { isArchived: true }));
    await assertFails(deleteDoc(doc(anon(), 'content_items/existing1')));
  });

  it('everything else stays closed to signed-out users', async () => {
    await assertFails(getDoc(doc(anon(), 'tutor_assignments/tutor1_s1')));
    await assertFails(getDocs(collection(anon(), 'tutors')));
    await assertFails(getDocs(collection(anon(), 'staff')));
    await assertFails(getDoc(doc(anon(), 'admins/legacy')));
  });
});
