// UHPAB (board) results. Students do not sign in and the records are private,
// so students reach them only through here, where unpaid fees block them.
//
//   POST /uhpab  { nsin }                                   published results
//   PUT, GET, DELETE /files/uhpab/{studentKey}/{docId}/{fileName}
//
// A student downloads with X-Student-NSIN. The Registrar uploads and deletes;
// the Registrar, Principal and Deputy download with their sign-in.

import { HttpError } from './common.js';
import { read, query } from './fees.js';

const READERS = ['principal', 'deputyPrincipal', 'registrar'];

// Same id as StudentNumber.bioKey in the app.
const studentKey = (nsin) =>
  nsin.includes('/') ? nsin.replaceAll('/', '_') : `N_${nsin}`;
const clean = (nsin) => String(nsin ?? '').trim().toUpperCase();

// Open only if every fee record is paid in full, however small the balance,
// or the Bursar has allowed this student. No fee record means blocked.
async function isBlocked(env, nsin) {
  if ((await read(env, `result_clearance/${studentKey(nsin)}`))?.allowed === true) {
    return false;
  }
  const records = await query(env, '', {
    from: [{ collectionId: 'student_fees' }],
    where: { fieldFilter: {
      field: { fieldPath: 'nsin' }, op: 'EQUAL', value: { stringValue: nsin },
    } },
  });
  return !records.length ||
    !records.every((r) => r.tuition > 0 && r.paid >= r.tuition);
}

const published = (map) =>
  Object.entries(map || {}).filter(([, v]) => v?.published === true);

async function activeStudent(findStudent, env, nsin) {
  const student = nsin ? await findStudent(env, nsin) : null;
  if (student?.status !== 'active') {
    throw new HttpError(403, 'You do not have access to these results.');
  }
}

export async function uhpabResults(request, env, { findStudent }) {
  let body;
  try {
    const text = await request.text();
    if (text.length > 1000) throw new Error('too long');
    body = JSON.parse(text);
  } catch {
    throw new HttpError(400, 'Invalid request.');
  }
  const nsin = clean(body?.nsin);
  if (!/^[A-Z0-9][A-Z0-9/.\-]{2,29}$/.test(nsin)) {
    throw new HttpError(400, 'Invalid request.');
  }
  await activeStudent(findStudent, env, nsin);

  const record = await read(env, `uhpab_results/${studentKey(nsin)}`);
  const units = published(record?.units);
  const documents = published(record?.documents);
  // Nothing about the results is sent while they are blocked.
  const blocked = units.length + documents.length > 0 && (await isBlocked(env, nsin));
  return Response.json({
    blocked,
    units: blocked ? [] : units.map(([subjectId, u]) => ({
      subjectId, subjectName: u.subjectName, year: u.year, semester: u.semester,
      mark: u.mark,
    })),
    documents: blocked ? [] : documents.map(([id, d]) => ({
      id, name: d.name, title: d.title,
    })),
  }, { headers: { 'Cache-Control': 'no-store' } });
}

function parse(pathname) {
  let parts;
  try {
    parts = pathname.slice('/files/'.length).split('/').map(decodeURIComponent);
  } catch {
    return null;
  }
  const [, owner, docId, name, ...rest] = parts;
  if (
    rest.length ||
    !/^[A-Za-z0-9._-]{1,128}$/.test(owner || '') || owner === '.' || owner === '..' ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(docId || '') ||
    !name || name === '.' || name === '..' || name.length > 200 ||
    /[\/\\\u0000-\u001f]/.test(name)
  ) return null;
  return { key: parts.join('/'), owner, docId, name };
}

export async function uhpabFile(request, env, pathname, tools) {
  const file = parse(pathname);
  if (!file) throw new HttpError(404, 'Not found.');
  if (!['GET', 'PUT', 'DELETE'].includes(request.method)) {
    throw new HttpError(405, 'Method not allowed.');
  }
  const denied = new HttpError(403, 'You do not have access to this file.');
  const auth = request.headers.get('Authorization') || '';

  if (auth.startsWith('Bearer ')) {
    const token = auth.slice(7);
    const uid = await tools.verifyIdToken(token, env.FIREBASE_PROJECT_ID);
    const fields = (await tools.getDocument(env, `staff/${uid}`, token))?.fields;
    const role = fields?.status?.stringValue === 'active' ? fields.role?.stringValue : null;
    if (request.method === 'GET') {
      if (!READERS.includes(role)) throw denied;
      return tools.download(env, file);
    }
    if (role !== 'registrar') throw denied;
    if (request.method === 'DELETE') return tools.remove(env, file, { uid, admin: true });
    return tools.upload(request, env, file, { uid });
  }

  const nsin = clean(request.headers.get('X-Student-NSIN'));
  if (!nsin) throw new HttpError(401, 'Sign in to use files.');
  if (request.method !== 'GET' || studentKey(nsin) !== file.owner) throw denied;
  await activeStudent(tools.findStudent, env, nsin);
  const record = await read(env, `uhpab_results/${file.owner}`);
  const listed = record?.documents?.[file.docId];
  if (listed?.published !== true || listed.name !== file.name) {
    throw new HttpError(404, 'File not found.');
  }
  if (await isBlocked(env, nsin)) {
    throw new HttpError(403, 'Your results are held until your fees are cleared. See the Bursar.');
  }
  return tools.download(env, file);
}
