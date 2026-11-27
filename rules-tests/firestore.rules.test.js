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
  writeBatch,
  query,
  where,
  Timestamp,
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
    await setDoc(doc(db, 'system/setup'), { principalUid: 'principal1', createdAt: new Date() });
    await setDoc(doc(db, 'staff/principal1'), staff('Principal', 'principal'));
    await setDoc(doc(db, 'staff/registrar1'), staff('Registrar', 'registrar'));
    await setDoc(doc(db, 'staff/registrar2'), staff('Suspended', 'registrar', 'suspended'));
    await setDoc(doc(db, 'staff/bursar1'), staff('Bursar', 'bursar'));
    await setDoc(doc(db, 'staff/deputy1'), staff('Deputy', 'deputyPrincipal'));
    await setDoc(doc(db, 'staff/deputy2'), staff('Terminated', 'deputyPrincipal', 'suspended'));
    await setDoc(doc(db, 'staff/askari1'), { ...staff('Askari', 'staffMember'), position: 'Askari' });
    await setDoc(doc(db, 'tutors/tutor1'), { name: 'T', email: 't@example.com', status: 'active' });
    await setDoc(doc(db, 'tutors/tutor2'), { name: 'S', email: 's@example.com', status: 'suspended' });
    await setDoc(doc(db, 'tutors/tutor3'), { name: 'U', email: 'u@example.com', status: 'active' });
    await setDoc(doc(db, 'tutor_assignments/tutor1_s1'), { tutorId: 'tutor1', subjectId: 's1' });
    await setDoc(doc(db, 'tutor_assignments/tutor2_s1'), { tutorId: 'tutor2', subjectId: 's1' });
    await setDoc(doc(db, 'public_posts/pub1'), { ...basePost('tutor1', 'T', 'tutor'), status: 'published', createdAt: new Date() });
    await setDoc(doc(db, 'public_posts/pend1'), { ...basePost('tutor1', 'T', 'tutor'), status: 'pending', createdAt: new Date() });
    await setDoc(doc(db, 'timetables/tt_draft'), { ...ttBase('registrar1'), status: 'draft', createdAt: new Date(), updatedAt: new Date() });
    await setDoc(doc(db, 'timetables/tt_pub'), { ...ttBase('registrar1'), status: 'published', createdAt: new Date(), updatedAt: new Date() });
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

const basePost = (authorId, authorName, authorRole) => ({
  title: 'Open day',
  body: 'Everyone is welcome.',
  category: 'announcement',
  authorId,
  authorName,
  authorRole,
});

const newPost = (authorId, authorName, authorRole, status, extra = {}) => ({
  ...basePost(authorId, authorName, authorRole),
  status,
  createdAt: serverTimestamp(),
  ...extra,
});

const ttBase = (uid) => ({
  title: 'Class Timetable',
  type: 'class',
  audience: 'students',
  status: 'draft',
  rows: 2,
  cols: 2,
  colWidths: [120, 120],
  cells: { r0c0: { t: 'Time', B: true } },
  footnotes: [],
  createdBy: uid,
  updatedBy: uid,
});

const newTimetable = (uid, extra = {}) => ({
  ...ttBase(uid),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...extra,
});

const ttEdit = (uid, extra = {}) => ({
  title: 'Edited title',
  updatedAt: serverTimestamp(),
  updatedBy: uid,
  ...extra,
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

describe('deputy principal and custom positions (staff)', () => {
  const withPosition = (data, position) => ({ ...data, position });

  it('the deputy can read any staff record and list staff', async () => {
    await assertSucceeds(getDoc(doc(as('deputy1'), 'staff/bursar1')));
    await assertSucceeds(getDoc(doc(as('deputy1'), 'staff/principal1')));
    await assertSucceeds(getDocs(collection(as('deputy1'), 'staff')));
  });

  it('custom-position staff can read only their own record and cannot list', async () => {
    await assertSucceeds(getDoc(doc(as('askari1'), 'staff/askari1')));
    await assertFails(getDoc(doc(as('askari1'), 'staff/bursar1')));
    await assertFails(getDocs(collection(as('askari1'), 'staff')));
  });

  it('the principal can appoint the deputy and add custom-position staff', async () => {
    const db = as('principal1');
    await assertSucceeds(setDoc(doc(db, 'staff/dep9'), newStaff('principal1', 'deputyPrincipal')));
    await assertSucceeds(setDoc(doc(db, 'staff/ask9'), withPosition(newStaff('principal1', 'staffMember'), 'Askari')));
  });

  it('the deputy can add registrar, bursar and custom-position staff, but not another deputy or a principal', async () => {
    const db = as('deputy1');
    await assertSucceeds(setDoc(doc(db, 'staff/n1'), newStaff('deputy1', 'registrar')));
    await assertSucceeds(setDoc(doc(db, 'staff/n2'), newStaff('deputy1', 'bursar')));
    await assertSucceeds(setDoc(doc(db, 'staff/n3'), withPosition(newStaff('deputy1', 'staffMember'), 'Accountant')));
    await assertFails(setDoc(doc(db, 'staff/n4'), newStaff('deputy1', 'deputyPrincipal')));
    await assertFails(setDoc(doc(db, 'staff/n5'), newStaff('deputy1', 'principal')));
  });

  it('nobody else can create staff, including custom-position staff', async () => {
    const rec = withPosition(newStaff('askari1', 'staffMember'), 'Askari');
    await assertFails(setDoc(doc(as('askari1'), 'staff/m1'), rec));
    await assertFails(setDoc(doc(as('registrar1'), 'staff/m2'), withPosition(newStaff('registrar1', 'staffMember'), 'Askari')));
    await assertFails(setDoc(doc(as('tutor1'), 'staff/m3'), withPosition(newStaff('tutor1', 'staffMember'), 'Askari')));
    await assertFails(setDoc(doc(anon(), 'staff/m4'), withPosition(newStaff('principal1', 'staffMember'), 'Askari')));
  });

  it('a custom position needs a sensible title, and only custom-position staff carry one', async () => {
    const db = as('principal1');
    await assertFails(setDoc(doc(db, 'staff/p1'), newStaff('principal1', 'staffMember')));
    await assertFails(setDoc(doc(db, 'staff/p2'), withPosition(newStaff('principal1', 'staffMember'), 'A')));
    await assertFails(setDoc(doc(db, 'staff/p3'), withPosition(newStaff('principal1', 'staffMember'), 'x'.repeat(61))));
    await assertFails(setDoc(doc(db, 'staff/p4'), withPosition(newStaff('principal1', 'staffMember'), 42)));
    await assertFails(setDoc(doc(db, 'staff/p5'), withPosition(newStaff('principal1', 'registrar'), 'Askari')));
  });

  it('the deputy can suspend and reactivate registrar, bursar and custom-position staff', async () => {
    const db = as('deputy1');
    await assertSucceeds(updateDoc(doc(db, 'staff/bursar1'), statusChange('deputy1', 'suspended')));
    await assertSucceeds(updateDoc(doc(db, 'staff/askari1'), statusChange('deputy1', 'suspended')));
    await assertSucceeds(updateDoc(doc(db, 'staff/registrar2'), statusChange('deputy1', 'active')));
  });

  it('the deputy cannot touch the principal or the deputy record', async () => {
    const db = as('deputy1');
    await assertFails(updateDoc(doc(db, 'staff/principal1'), statusChange('deputy1', 'suspended')));
    await assertFails(updateDoc(doc(db, 'staff/deputy1'), statusChange('deputy1', 'suspended')));
    await assertFails(updateDoc(doc(db, 'staff/deputy2'), statusChange('deputy1', 'active')));
  });

  it('only the principal can terminate the deputy, and termination is one-way', async () => {
    await assertSucceeds(updateDoc(doc(as('principal1'), 'staff/deputy1'), statusChange('principal1', 'suspended')));
    await assertFails(updateDoc(doc(as('principal1'), 'staff/deputy2'), statusChange('principal1', 'active')));
    await assertFails(updateDoc(doc(as('registrar1'), 'staff/deputy1'), statusChange('registrar1', 'suspended')));
    await assertFails(updateDoc(doc(as('askari1'), 'staff/deputy1'), statusChange('askari1', 'suspended')));
  });

  it('a terminated deputy loses all staff powers at once', async () => {
    await assertSucceeds(updateDoc(doc(as('principal1'), 'staff/deputy1'), statusChange('principal1', 'suspended')));
    await assertFails(getDocs(collection(as('deputy1'), 'staff')));
    await assertFails(setDoc(doc(as('deputy1'), 'staff/late1'), newStaff('deputy1', 'registrar')));
    await assertFails(setDoc(doc(as('deputy1'), 'subjects/late2'), subject));
  });

  it('custom-position staff cannot change anyone\'s status', async () => {
    await assertFails(updateDoc(doc(as('askari1'), 'staff/bursar1'), statusChange('askari1', 'suspended')));
    await assertFails(updateDoc(doc(as('askari1'), 'staff/askari1'), statusChange('askari1', 'active')));
  });
});

describe('staff_positions (the list on the Staff screen)', () => {
  const newPosition = (createdBy, title = 'Askari') => ({
    title,
    createdAt: serverTimestamp(),
    createdBy,
  });

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'staff_positions/pos1'), { title: 'Accountant', createdBy: 'principal1', createdAt: new Date() });
    });
  });

  it('anyone can read the list without signing in', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'staff_positions/pos1')));
    await assertSucceeds(getDocs(collection(anon(), 'staff_positions')));
  });

  it('the principal and the deputy can add a position', async () => {
    await assertSucceeds(setDoc(doc(as('principal1'), 'staff_positions/a1'), newPosition('principal1')));
    await assertSucceeds(setDoc(doc(as('deputy1'), 'staff_positions/a2'), newPosition('deputy1', 'Clinical Instructor')));
  });

  it('nobody else can add a position', async () => {
    await assertFails(setDoc(doc(as('registrar1'), 'staff_positions/b1'), newPosition('registrar1')));
    await assertFails(setDoc(doc(as('bursar1'), 'staff_positions/b2'), newPosition('bursar1')));
    await assertFails(setDoc(doc(as('askari1'), 'staff_positions/b3'), newPosition('askari1')));
    await assertFails(setDoc(doc(as('tutor1'), 'staff_positions/b4'), newPosition('tutor1')));
    await assertFails(setDoc(doc(anon(), 'staff_positions/b5'), newPosition('principal1')));
    await assertFails(setDoc(doc(as('registrar2'), 'staff_positions/b6'), newPosition('registrar2')));
  });

  it('a position must be well-formed', async () => {
    const db = as('principal1');
    await assertFails(setDoc(doc(db, 'staff_positions/c1'), newPosition('principal1', 'A')));
    await assertFails(setDoc(doc(db, 'staff_positions/c2'), newPosition('principal1', 'x'.repeat(61))));
    await assertFails(setDoc(doc(db, 'staff_positions/c3'), newPosition('someone-else')));
    await assertFails(setDoc(doc(db, 'staff_positions/c4'), { ...newPosition('principal1'), extra: true }));
    await assertFails(setDoc(doc(db, 'staff_positions/c5'), { ...newPosition('principal1'), createdAt: new Date(0) }));
  });

  it('positions are never edited; the principal and deputy can remove them, nobody else', async () => {
    await assertFails(updateDoc(doc(as('principal1'), 'staff_positions/pos1'), { title: 'Renamed' }));
    await assertFails(deleteDoc(doc(as('registrar1'), 'staff_positions/pos1')));
    await assertFails(deleteDoc(doc(as('askari1'), 'staff_positions/pos1')));
    await assertFails(deleteDoc(doc(anon(), 'staff_positions/pos1')));
    await assertSucceeds(deleteDoc(doc(as('deputy1'), 'staff_positions/pos1')));
  });
});

describe('deputy principal in the rest of the app', () => {
  it('the deputy can create and edit academic structure like the principal', async () => {
    await assertSucceeds(setDoc(doc(as('deputy1'), 'subjects/ds1'), subject));
    await assertSucceeds(updateDoc(doc(as('deputy1'), 'students/stu1'), { status: 'suspended' }));
  });

  it('custom-position staff cannot write academic structure', async () => {
    await assertFails(setDoc(doc(as('askari1'), 'subjects/ds2'), subject));
    await assertFails(updateDoc(doc(as('askari1'), 'students/stu1'), { status: 'suspended' }));
  });

  it('the deputy publishes to the Public Space as themselves, like the principal', async () => {
    await assertSucceeds(setDoc(doc(as('deputy1'), 'public_posts/d1'), newPost('deputy1', 'Deputy', 'deputyPrincipal', 'published')));
    await assertFails(setDoc(doc(as('deputy1'), 'public_posts/d2'), newPost('deputy1', 'Deputy', 'principal', 'published')));
  });

  it('custom-position staff can read the Public Space but cannot post', async () => {
    await assertSucceeds(getDoc(doc(as('askari1'), 'public_posts/pub1')));
    await assertFails(setDoc(doc(as('askari1'), 'public_posts/k1'), newPost('askari1', 'Askari', 'staffMember', 'published')));
    await assertFails(setDoc(doc(as('askari1'), 'public_posts/k2'), newPost('askari1', 'Askari', 'staffMember', 'pending')));
  });

  it('the deputy moderates like the principal; custom-position staff cannot', async () => {
    const stamp = (uid, status) => ({ status, reviewedBy: uid, reviewedAt: serverTimestamp() });
    // Custom-position staff first: once the deputy publishes pend1 it is
    // public and anyone could read it.
    await assertFails(getDoc(doc(as('askari1'), 'public_posts/pend1')));
    await assertFails(updateDoc(doc(as('askari1'), 'public_posts/pend1'), stamp('askari1', 'published')));
    await assertFails(deleteDoc(doc(as('askari1'), 'public_posts/pend1')));
    await assertSucceeds(getDoc(doc(as('deputy1'), 'public_posts/pend1')));
    await assertSucceeds(updateDoc(doc(as('deputy1'), 'public_posts/pend1'), stamp('deputy1', 'published')));
    await assertSucceeds(deleteDoc(doc(as('deputy1'), 'public_posts/pub1')));
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

describe('public space (public_posts)', () => {
  const published = (db) =>
    query(collection(db, 'public_posts'), where('status', '==', 'published'));

  it('anyone can read published posts, signed in or not', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'public_posts/pub1')));
    await assertSucceeds(getDocs(published(anon())));
    await assertSucceeds(getDocs(published(as('tutor3'))));
  });

  it('the public cannot read pending posts or list without the published filter', async () => {
    await assertFails(getDoc(doc(anon(), 'public_posts/pend1')));
    await assertFails(getDocs(collection(anon(), 'public_posts')));
    await assertFails(getDoc(doc(as('tutor3'), 'public_posts/pend1')));
  });

  it('the author and moderators can read a pending post', async () => {
    await assertSucceeds(getDoc(doc(as('tutor1'), 'public_posts/pend1')));
    await assertSucceeds(getDoc(doc(as('principal1'), 'public_posts/pend1')));
    await assertSucceeds(getDoc(doc(as('registrar1'), 'public_posts/pend1')));
    await assertFails(getDoc(doc(as('bursar1'), 'public_posts/pend1')));
  });

  it('principal, registrar and bursar publish directly as themselves', async () => {
    await assertSucceeds(setDoc(doc(as('principal1'), 'public_posts/n1'), newPost('principal1', 'Principal', 'principal', 'published')));
    await assertSucceeds(setDoc(doc(as('registrar1'), 'public_posts/n2'), newPost('registrar1', 'Registrar', 'registrar', 'published')));
    await assertSucceeds(setDoc(doc(as('bursar1'), 'public_posts/n3'), newPost('bursar1', 'Bursar', 'bursar', 'published')));
  });

  it('staff cannot spoof their name, role or author, or post as pending', async () => {
    await assertFails(setDoc(doc(as('bursar1'), 'public_posts/s1'), newPost('bursar1', 'The Principal', 'bursar', 'published')));
    await assertFails(setDoc(doc(as('bursar1'), 'public_posts/s2'), newPost('bursar1', 'Bursar', 'principal', 'published')));
    await assertFails(setDoc(doc(as('bursar1'), 'public_posts/s3'), newPost('principal1', 'Bursar', 'bursar', 'published')));
    await assertFails(setDoc(doc(as('bursar1'), 'public_posts/s4'), newPost('bursar1', 'Bursar', 'bursar', 'pending')));
  });

  it('an active tutor can only submit pending posts', async () => {
    await assertSucceeds(setDoc(doc(as('tutor1'), 'public_posts/t1'), newPost('tutor1', 'T', 'tutor', 'pending')));
    await assertFails(setDoc(doc(as('tutor1'), 'public_posts/t2'), newPost('tutor1', 'T', 'tutor', 'published')));
  });

  it('suspended tutors, strangers and signed-out users cannot post', async () => {
    await assertFails(setDoc(doc(as('tutor2'), 'public_posts/x1'), newPost('tutor2', 'S', 'tutor', 'pending')));
    await assertFails(setDoc(doc(as('attacker'), 'public_posts/x2'), newPost('attacker', 'A', 'tutor', 'pending')));
    await assertFails(setDoc(doc(anon(), 'public_posts/x3'), newPost('tutor1', 'T', 'tutor', 'pending')));
  });

  it('posts must be well-formed', async () => {
    const db = as('principal1');
    const ok = (extra) => newPost('principal1', 'Principal', 'principal', 'published', extra);
    await assertFails(setDoc(doc(db, 'public_posts/b1'), ok({ title: 'Hi' })));
    await assertFails(setDoc(doc(db, 'public_posts/b2'), ok({ category: 'spam' })));
    await assertFails(setDoc(doc(db, 'public_posts/b3'), ok({ body: '' })));
    await assertFails(setDoc(doc(db, 'public_posts/b4'), ok({ extra: 1 })));
    await assertFails(setDoc(doc(db, 'public_posts/b5'), ok({ createdAt: new Date(0) })));
    await assertFails(setDoc(doc(db, 'public_posts/b6'), ok({ imageUrl: 'http://example.com/a.jpg' })));
    await assertSucceeds(setDoc(doc(db, 'public_posts/b7'), ok({ imageUrl: 'https://example.com/a.jpg' })));
  });

  it('events need a date and gallery posts need an image', async () => {
    const db = as('principal1');
    const ok = (extra) => newPost('principal1', 'Principal', 'principal', 'published', extra);
    await assertFails(setDoc(doc(db, 'public_posts/e1'), ok({ category: 'event' })));
    await assertSucceeds(setDoc(doc(db, 'public_posts/e2'), ok({ category: 'event', eventDate: Timestamp.fromDate(new Date('2027-03-01')) })));
    await assertFails(setDoc(doc(db, 'public_posts/g1'), ok({ category: 'gallery' })));
    await assertSucceeds(setDoc(doc(db, 'public_posts/g2'), ok({ category: 'gallery', imageUrl: 'https://example.com/p.jpg' })));
  });

  it('principal and registrar approve or archive; nobody else can', async () => {
    const stamp = (uid, status) => ({ status, reviewedBy: uid, reviewedAt: serverTimestamp() });
    await assertSucceeds(updateDoc(doc(as('principal1'), 'public_posts/pend1'), stamp('principal1', 'published')));
    await assertSucceeds(updateDoc(doc(as('registrar1'), 'public_posts/pub1'), stamp('registrar1', 'archived')));
    await assertFails(updateDoc(doc(as('bursar1'), 'public_posts/pend1'), stamp('bursar1', 'published')));
    await assertFails(updateDoc(doc(as('tutor3'), 'public_posts/pend1'), stamp('tutor3', 'published')));
    await assertFails(updateDoc(doc(as('tutor1'), 'public_posts/pend1'), stamp('tutor1', 'published')));
  });

  it('an author can withdraw their own post but not publish it or edit it', async () => {
    await assertSucceeds(updateDoc(doc(as('tutor1'), 'public_posts/pend1'), { status: 'archived' }));
    await assertFails(updateDoc(doc(as('tutor1'), 'public_posts/pend1'), { status: 'published' }));
    await assertFails(updateDoc(doc(as('tutor1'), 'public_posts/pub1'), { title: 'Edited' }));
    await assertFails(updateDoc(doc(as('tutor3'), 'public_posts/pub1'), { status: 'archived' }));
  });

  it('only principal and registrar can delete', async () => {
    await assertSucceeds(deleteDoc(doc(as('registrar1'), 'public_posts/pub1')));
    await assertFails(deleteDoc(doc(as('tutor1'), 'public_posts/pend1')));
    await assertFails(deleteDoc(doc(anon(), 'public_posts/pend1')));
  });
});

describe('student fees', () => {
  const id = 'PN12345_Y1S1';
  const feePath = `student_fees/${id}`;
  const as = (uid) => env.authenticatedContext(uid).firestore();
  const stamp = (uid) => ({ updatedBy: uid, updatedAt: serverTimestamp() });
  const record = (extra = {}) => ({
    paymentNumber: 'PN12345', nsin: 'JAN26/U028/MCK/001', name: 'Mary Achieng',
    programType: 'certificateNursing', year: 1, semester: 1,
    tuition: 1000, paid: 0, ...stamp('bursar1'), ...extra,
  });
  const open = (extra = {}, owner = 'JAN26/U028/MCK/001') => {
    const db = as('bursar1');
    const batch = writeBatch(db);
    batch.set(doc(db, 'fee_numbers/PN12345'), { nsin: owner, ...stamp('bursar1') });
    batch.set(doc(db, feePath), record(extra));
    return batch.commit();
  };
  const pay = (amount, paid, { pid = 'p1', method = 'bank' } = {}) => {
    const db = as('bursar1');
    const batch = writeBatch(db);
    batch.set(doc(db, `${feePath}/payments/${pid}`), {
      amount, method, reference: 'R1', recordedBy: 'bursar1', createdAt: serverTimestamp(),
    });
    batch.update(doc(db, feePath), { paid, lastPaymentId: pid, ...stamp('bursar1') });
    return batch.commit();
  };

  it('the bursar can open a record', async () => {
    await assertSucceeds(open());
  });
  it('rejects a wrong id, money already paid, or extra fields', async () => {
    await assertFails(open({ paymentNumber: 'OTHER1' }));
    await assertFails(open({ paid: 5 }));
    await assertFails(open({ note: 'x' }));
    await assertFails(open({}, 'JAN26/U028/MCK/002'));
    await assertFails(setDoc(doc(as('bursar1'), feePath), record()));
  });
  it('only the bursar writes; only bursar and principal level read', async () => {
    await assertSucceeds(open());
    for (const uid of ['principal1', 'deputy1', 'registrar1', 'tutor1']) {
      await assertFails(updateDoc(doc(as(uid), feePath), { tuition: 1, ...stamp(uid) }));
    }
    await assertSucceeds(getDoc(doc(as('principal1'), feePath)));
    await assertSucceeds(getDocs(collection(as('bursar1'), 'student_fees')));
    for (const uid of ['registrar1', 'askari1']) {
      await assertFails(getDocs(collection(as(uid), 'student_fees')));
    }
    await assertFails(getDocs(collection(as('tutor1'), 'student_fees')));
  });
  it('keeps fee data from anyone signed out', async () => {
    await assertSucceeds(open());
    await assertSucceeds(pay(400, 400));
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, feePath)));
    await assertFails(getDocs(collection(db, `${feePath}/payments`)));
    await assertFails(getDoc(doc(db, 'fee_numbers/PN12345')));
  });
  it('only the bursar records guardians; only the registrar side records bio', async () => {
    const names = (uid) => setDoc(doc(as(uid), 'fee_guardians/PN12345'),
      { names: ['John Okot'], ...stamp(uid) });
    const bio = (uid) => setDoc(doc(as(uid), 'student_bio/PN12345'),
      { dateOfBirth: '2006-03-14', district: 'Gulu', village: 'Pece',
        primarySchool: 'P', secondarySchool: 'S', ...stamp(uid) });
    await assertSucceeds(names('bursar1'));
    await assertFails(names('registrar1'));
    await assertSucceeds(bio('registrar1'));
    await assertFails(bio('bursar1'));
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'fee_guardians/PN12345')));
    await assertFails(getDoc(doc(db, 'student_bio/PN12345')));
    await assertFails(getDoc(doc(db, 'fee_attempts/PN12345_2026-01-01')));
  });
  it('lets the bursar change tuition for a whole class at once', async () => {
    const db = as('bursar1');
    const ids = Array.from({ length: 30 }, (_, i) => `CLS${100 + i}`);
    for (const code of ids) {
      const batch = writeBatch(db);
      batch.set(doc(db, `fee_numbers/${code}`), { nsin: '', ...stamp('bursar1') });
      batch.set(doc(db, `student_fees/${code}_Y1S1`),
        record({ paymentNumber: code, nsin: '' }));
      await assertSucceeds(batch.commit());
    }
    const bulk = writeBatch(db);
    for (const code of ids) {
      bulk.update(doc(db, `student_fees/${code}_Y1S1`),
        { tuition: 2000, ...stamp('bursar1') });
    }
    await assertSucceeds(bulk.commit());
  });
  it('never deletes', async () => {
    await assertSucceeds(open());
    await assertSucceeds(pay(400, 400));
    await assertFails(deleteDoc(doc(as('bursar1'), feePath)));
    await assertFails(deleteDoc(doc(as('bursar1'), `${feePath}/payments/p1`)));
  });
});

describe('timetables (Registrar builds, everyone reads published)', () => {
  const publishedQuery = (db) =>
    query(collection(db, 'timetables'), where('status', '==', 'published'));

  it('anyone can read a published timetable, signed in or not', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'timetables/tt_pub')));
    await assertSucceeds(getDocs(publishedQuery(anon())));
    await assertSucceeds(getDoc(doc(as('tutor1'), 'timetables/tt_pub')));
  });

  it('drafts are hidden from the public, tutors and the bursar', async () => {
    await assertFails(getDoc(doc(anon(), 'timetables/tt_draft')));
    await assertFails(getDocs(collection(anon(), 'timetables')));
    await assertFails(getDoc(doc(as('tutor1'), 'timetables/tt_draft')));
    await assertFails(getDoc(doc(as('bursar1'), 'timetables/tt_draft')));
  });

  it('the registrar, principal and deputy can read drafts', async () => {
    await assertSucceeds(getDoc(doc(as('registrar1'), 'timetables/tt_draft')));
    await assertSucceeds(getDoc(doc(as('principal1'), 'timetables/tt_draft')));
    await assertSucceeds(getDoc(doc(as('deputy1'), 'timetables/tt_draft')));
    await assertSucceeds(getDocs(collection(as('registrar1'), 'timetables')));
  });

  it('only the registrar can create a timetable', async () => {
    await assertSucceeds(setDoc(doc(as('registrar1'), 'timetables/new1'), newTimetable('registrar1')));
    await assertFails(setDoc(doc(as('principal1'), 'timetables/new2'), newTimetable('principal1')));
    await assertFails(setDoc(doc(as('deputy1'), 'timetables/new3'), newTimetable('deputy1')));
    await assertFails(setDoc(doc(as('bursar1'), 'timetables/new4'), newTimetable('bursar1')));
    await assertFails(setDoc(doc(as('tutor1'), 'timetables/new5'), newTimetable('tutor1')));
    await assertFails(setDoc(doc(as('registrar2'), 'timetables/new6'), newTimetable('registrar2')));
    await assertFails(setDoc(doc(anon(), 'timetables/new7'), newTimetable('registrar1')));
  });

  it('a timetable must be well-formed', async () => {
    const db = as('registrar1');
    const bad = (extra) => setDoc(doc(db, 'timetables/bad'), newTimetable('registrar1', extra));
    await assertFails(bad({ title: 'Hi' }));
    await assertFails(bad({ type: 'weird' }));
    await assertFails(bad({ audience: 'nobody' }));
    await assertFails(bad({ rows: 0 }));
    await assertFails(bad({ rows: 61 }));
    await assertFails(bad({ cols: 21, colWidths: new Array(21).fill(100) }));
    await assertFails(bad({ colWidths: [120] }));
    await assertFails(bad({ extra: 1 }));
    await assertFails(bad({ createdBy: 'someone-else' }));
    await assertFails(bad({ createdAt: new Date(0) }));
    await assertFails(bad({ footnotes: new Array(13).fill('x') }));
    await assertSucceeds(bad({ subtitle: 'Year 1', academicYear: '2026/27', programType: 'certificateNursing', year: 1, semester: 2 }));
  });

  it('the registrar can edit, publish and delete; nobody else can', async () => {
    await assertSucceeds(updateDoc(doc(as('registrar1'), 'timetables/tt_draft'), ttEdit('registrar1')));
    await assertSucceeds(updateDoc(doc(as('registrar1'), 'timetables/tt_draft'), ttEdit('registrar1', { status: 'published', publishedAt: serverTimestamp() })));
    await assertFails(updateDoc(doc(as('principal1'), 'timetables/tt_pub'), ttEdit('principal1')));
    await assertFails(updateDoc(doc(as('deputy1'), 'timetables/tt_pub'), ttEdit('deputy1')));
    await assertFails(updateDoc(doc(as('registrar2'), 'timetables/tt_pub'), ttEdit('registrar2')));
    await assertFails(updateDoc(doc(as('tutor1'), 'timetables/tt_pub'), ttEdit('tutor1')));
    await assertFails(updateDoc(doc(anon(), 'timetables/tt_pub'), ttEdit('registrar1')));
    await assertSucceeds(deleteDoc(doc(as('registrar1'), 'timetables/tt_draft')));
    await assertFails(deleteDoc(doc(as('principal1'), 'timetables/tt_pub')));
    await assertFails(deleteDoc(doc(anon(), 'timetables/tt_pub')));
  });

  it('edits cannot rewrite who created it or when, or spoof the editor', async () => {
    const db = as('registrar1');
    await assertFails(updateDoc(doc(db, 'timetables/tt_pub'), ttEdit('registrar1', { createdBy: 'principal1' })));
    await assertFails(updateDoc(doc(db, 'timetables/tt_pub'), ttEdit('principal1')));
    await assertFails(updateDoc(doc(db, 'timetables/tt_pub'), ttEdit('registrar1', { updatedAt: new Date(0) })));
    await assertFails(updateDoc(doc(db, 'timetables/tt_pub'), ttEdit('registrar1', { rows: 99 })));
  });
});

// ---------------------------------------------------------------------
// First-run Principal setup. The seed above models a school that already
// has its Principal (system/setup exists); these tests remove the marker
// to model a brand-new, empty school.
// ---------------------------------------------------------------------
describe('first-run Principal setup', () => {
  const principalRecord = (uid) => ({
    name: 'Grace Namuli',
    email: 'grace@example.com',
    role: 'principal',
    status: 'active',
    createdAt: serverTimestamp(),
    createdBy: uid,
  });
  const marker = (uid) => ({ principalUid: uid, createdAt: serverTimestamp() });

  const freshSchool = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'system/setup'));
    });

  const register = (uid, record = principalRecord(uid), mark = marker(uid)) => {
    const db = as(uid);
    const batch = writeBatch(db);
    batch.set(doc(db, 'system/setup'), mark);
    batch.set(doc(db, 'staff/' + uid), record);
    return batch.commit();
  };

  it('anyone can read the setup marker but nobody can list or list-read system', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'system/setup')));
    await assertFails(getDocs(collection(anon(), 'system')));
    await assertFails(getDoc(doc(anon(), 'system/other')));
  });

  it('on a fresh school, a new user registers as Principal in one batch', async () => {
    await freshSchool();
    await assertSucceeds(register('newprincipal'));
  });

  it('the marker alone, or the Principal record alone, is refused', async () => {
    await freshSchool();
    await assertFails(setDoc(doc(as('newprincipal'), 'system/setup'), marker('newprincipal')));
    await assertFails(setDoc(doc(as('newprincipal'), 'staff/newprincipal'), principalRecord('newprincipal')));
  });

  it('cannot register for someone else, or with a marker naming someone else', async () => {
    await freshSchool();
    const db = as('attacker');
    const batch = writeBatch(db);
    batch.set(doc(db, 'system/setup'), marker('victim'));
    batch.set(doc(db, 'staff/victim'), principalRecord('victim'));
    await assertFails(batch.commit());
    await assertFails(register('attacker', principalRecord('attacker'), marker('someoneelse')));
  });

  it('the record must be a clean active principal, not another role or extra fields', async () => {
    await freshSchool();
    await assertFails(register('u1', { ...principalRecord('u1'), role: 'registrar' }));
    await assertFails(register('u2', { ...principalRecord('u2'), status: 'suspended' }));
    await assertFails(register('u3', { ...principalRecord('u3'), position: 'Boss' }));
    await assertFails(register('u4', { ...principalRecord('u4'), createdBy: 'someoneelse' }));
  });

  it('once the school is set up, nobody can register as Principal again', async () => {
    await assertFails(register('latecomer'));
    await assertFails(setDoc(doc(as('latecomer'), 'staff/latecomer'), principalRecord('latecomer')));
  });

  it('the marker cannot be edited or deleted, even by the Principal', async () => {
    await assertFails(updateDoc(doc(as('principal1'), 'system/setup'), { principalUid: 'principal1' }));
    await assertFails(deleteDoc(doc(as('principal1'), 'system/setup')));
    await assertFails(setDoc(doc(as('principal1'), 'system/setup'), marker('principal1')));
  });

  it('tutors cannot register until the Principal has set the school up', async () => {
    const tutorDoc = { name: 'New Tutor', email: 'nt@example.com', status: 'active' };
    await freshSchool();
    await assertFails(setDoc(doc(as('newtutor'), 'tutors/newtutor'), tutorDoc));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'system/setup'), { principalUid: 'p', createdAt: new Date() });
    });
    await assertSucceeds(setDoc(doc(as('newtutor'), 'tutors/newtutor'), tutorDoc));
  });
});
