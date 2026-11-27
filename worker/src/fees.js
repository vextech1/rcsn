// Fee details for parents, guardians and students. Records are private in
// Firestore; this reads them with a service account and returns them only to a
// caller who passes the check.
//
//   POST /fees  { code, nsin }                      signed-in student
//   POST /fees  { code, guardian, answers: {..} }   everyone else
//
// `answers` holds exactly two of ANSWER_FIELDS.

import { HttpError, firestoreBase } from './common.js';

const MAX_FAILURES = 5; // per payment code per day (UTC)
export const ANSWER_FIELDS = [
  'dateOfBirth', 'address', 'studentName', 'primarySchool', 'secondarySchool',
];

// Capitals, punctuation, extra spaces and word order do not matter.
const words = (text) =>
  String(text ?? '').toLowerCase().normalize('NFKD').replace(/\p{M}/gu, '')
    .split(/[^\p{L}\p{N}]+/u).filter(Boolean).sort().join(' ');

const same = (given, stored) => words(stored) !== '' && words(given) === words(stored);

// ---------------------------------------------------------------- Service account

let cached = { token: null, expires: 0, email: null };

const encode = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const encodeJson = (o) => encode(new TextEncoder().encode(JSON.stringify(o)));

async function serviceToken(env) {
  if (!env.FIREBASE_SERVICE_ACCOUNT) throw new HttpError(503, 'Fee lookup is not set up yet.');
  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  if (cached.email === account.client_email && Date.now() < cached.expires) return cached.token;

  const pem = account.private_key.replace(/-----[^-]+-----|\s/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8', Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const now = Math.floor(Date.now() / 1000);
  const body = `${encodeJson({ alg: 'RS256', typ: 'JWT' })}.${encodeJson({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
  })}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(body));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${body}.${encode(signature)}`,
    }),
  });
  if (!res.ok) throw new HttpError(503, 'Fee lookup is unavailable. Try again.');
  const data = await res.json();
  cached = {
    token: data.access_token,
    email: account.client_email,
    expires: Date.now() + 1000 * (data.expires_in - 60),
  };
  return cached.token;
}

// ---------------------------------------------------------------- Firestore

function plain(value) {
  if ('integerValue' in value) return Number(value.integerValue);
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(plain);
  return value.stringValue ?? value.timestampValue ?? null;
}
const fields = (doc) =>
  Object.fromEntries(Object.entries(doc.fields || {}).map(([k, v]) => [k, plain(v)]));

async function firestore(env, path, init = {}) {
  const res = await fetch(`${firestoreBase(env)}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${await serviceToken(env)}`,
      'Content-Type': 'application/json',
    },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new HttpError(503, 'Fee lookup is unavailable. Try again.');
  return res.json();
}

async function read(env, path) {
  const doc = await firestore(env, `/${path}`);
  return doc ? fields(doc) : null;
}

async function query(env, parent, structuredQuery) {
  const rows = await firestore(env, `${parent}:runQuery`, {
    method: 'POST', body: JSON.stringify({ structuredQuery }),
  });
  return (rows || []).filter((r) => r.document).map((r) => ({
    id: r.document.name.split('/').pop(), ...fields(r.document),
  }));
}

// Atomically adds to today's failure count and returns the new value, so that
// guesses sent in parallel cannot slip past the limit.
async function count(env, code, by) {
  const day = new Date().toISOString().slice(0, 10);
  const name = `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/fee_attempts/${code}_${day}`;
  const result = await firestore(env, ':commit', {
    method: 'POST',
    body: JSON.stringify({
      writes: [{
        transform: {
          document: name,
          fieldTransforms: [{ fieldPath: 'failures', increment: { integerValue: String(by) } }],
        },
      }],
    }),
  });
  return Number(result.writeResults[0].transformResults[0].integerValue);
}

// ---------------------------------------------------------------- Check

async function verify(env, body, records, code) {
  if (!records.length) return false;
  if (typeof body.nsin === 'string') {
    const nsin = body.nsin.trim().toUpperCase();
    return nsin !== '' && records.every((r) => r.nsin === '' || r.nsin === nsin) &&
      records.some((r) => r.nsin === nsin);
  }
  const guardians = (await read(env, `fee_guardians/${code}`))?.names || [];
  const nsin = records.find((r) => r.nsin)?.nsin;
  // The Registrar may have filed bio data under the NSIN or the payment code.
  const bio = {
    ...(await read(env, `student_bio/${code}`)),
    // Same id as StudentNumber.bioKey in the app.
    ...(nsin ? await read(env, `student_bio/${
      nsin.includes('/') ? nsin.replaceAll('/', '_') : `N_${nsin}`}`) : null),
  };
  const stored = {
    dateOfBirth: bio.dateOfBirth,
    address: bio.district && bio.village ? `${bio.district} ${bio.village}` : '',
    studentName: records[0].name,
    primarySchool: bio.primarySchool,
    secondarySchool: bio.secondarySchool,
  };
  // Evaluate everything before deciding.
  const results = [
    guardians.some((g) => same(body.guardian, g)),
    ...Object.entries(body.answers).map(([field, given]) => same(given, stored[field])),
  ];
  return results.every(Boolean);
}

export async function fees(request, env) {
  let body;
  try {
    const text = await request.text();
    if (text.length > 4000) throw new Error('too long');
    body = JSON.parse(text);
  } catch {
    throw new HttpError(400, 'Invalid request.');
  }
  const code = String(body?.code ?? '').replace(/\s/g, '').toUpperCase();
  if (!/^[A-Z0-9]{4,10}$/.test(code)) throw new HttpError(400, 'Enter a valid payment code.');
  if (typeof body.nsin !== 'string') {
    const keys = Object.keys(body.answers || {});
    if (typeof body.guardian !== 'string' || keys.length !== 2 ||
        !keys.every((k) => ANSWER_FIELDS.includes(k))) {
      throw new HttpError(400, 'Enter the parent or guardian names and answer two questions.');
    }
  }

  // Count the attempt first; a correct one is given back below.
  if ((await count(env, code, 1)) > MAX_FAILURES) {
    throw new HttpError(429, 'Too many wrong attempts. Try again tomorrow or see the Bursar.');
  }
  const records = await query(env, '', {
    from: [{ collectionId: 'student_fees' }],
    where: { fieldFilter: {
      field: { fieldPath: 'paymentNumber' }, op: 'EQUAL', value: { stringValue: code },
    } },
  });
  if (!(await verify(env, body, records, code))) {
    // Never say which part was wrong.
    throw new HttpError(403, 'Those details do not match our records.');
  }
  await count(env, code, -1);

  records.sort((a, b) => b.year - a.year || b.semester - a.semester);
  const out = [];
  for (const r of records) {
    const payments = await query(env, `/student_fees/${r.id}`, {
      from: [{ collectionId: 'payments' }],
      orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    });
    out.push({
      paymentNumber: code, nsin: r.nsin, name: r.name, programType: r.programType,
      year: r.year, semester: r.semester, tuition: r.tuition, paid: r.paid,
      payments: payments.map((p) => ({
        amount: p.amount, method: p.method, reference: p.reference, createdAt: p.createdAt,
      })),
    });
  }
  return Response.json({ records: out }, { headers: { 'Cache-Control': 'no-store' } });
}
