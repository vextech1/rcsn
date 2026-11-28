// RCSN file storage: a small gatekeeper in front of a private R2 bucket.
//
//   PUT    /files/subjects/{subjectId}/content/{fileName}   upload
//   GET    /files/subjects/{subjectId}/content/{fileName}   download
//   DELETE /files/subjects/{subjectId}/content/{fileName}   delete
//   PUT, GET, DELETE /files/public/{uid}/{postId}/{fileName}  public post files
//   /uhpab and /files/uhpab/...  UHPAB results (see uhpab.js)
//
// Callers prove who they are with either
//   Authorization: Bearer <Firebase ID token>   (staff and tutors), or
//   X-Student-NSIN: <nsin>                      (students, download only).
//
// Roles and assignments are read from Firestore over REST *as the caller*, so
// no service-account key is needed and the Firestore rules still apply.

// Cloudflare rejects request bodies over 100 MB on the free plan.
// Keep in step with UploadRules in the app.
const MAX_BYTES = 95 * 1024 * 1024;

const CONTENT_TYPES = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  heic: 'image/heic',
  pdf: 'application/pdf',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

import { HttpError, firestoreBase } from './common.js';
import { fees } from './fees.js';
import { publicFile } from './public.js';
import { uhpabFile, uhpabResults } from './uhpab.js';

const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

// ---------------------------------------------------------------- Firebase token

let jwks = { keys: [], expires: 0 };

async function signingKey(kid) {
  const find = () => jwks.keys.find((k) => k.kid === kid);
  if (Date.now() >= jwks.expires || !find()) {
    const res = await fetch(JWKS_URL);
    if (!res.ok) throw new HttpError(503, 'Could not check your sign-in. Try again.');
    const maxAge = /max-age=(\d+)/.exec(res.headers.get('cache-control') || '');
    jwks = {
      keys: (await res.json()).keys,
      expires: Date.now() + 1000 * (maxAge ? Number(maxAge[1]) : 3600),
    };
  }
  return find();
}

const b64url = (s) =>
  Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

async function verifyIdToken(token, projectId) {
  const bad = new HttpError(401, 'Your sign-in has expired. Sign in again.');
  let header, claims, signature, signed;
  try {
    const [h, p, s] = token.split('.');
    const decode = (part) => JSON.parse(new TextDecoder().decode(b64url(part)));
    header = decode(h);
    claims = decode(p);
    signature = b64url(s);
    signed = new TextEncoder().encode(`${h}.${p}`);
  } catch {
    throw bad;
  }
  const now = Math.floor(Date.now() / 1000);
  if (
    header.alg !== 'RS256' ||
    claims.aud !== projectId ||
    claims.iss !== `https://securetoken.google.com/${projectId}` ||
    typeof claims.sub !== 'string' || !claims.sub || claims.sub.includes('/') ||
    !(claims.exp > now) ||
    !(claims.iat <= now + 60)
  ) throw bad;

  const jwk = await signingKey(header.kid);
  if (!jwk) throw bad;
  const algorithm = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };
  const key = await crypto.subtle.importKey('jwk', jwk, algorithm, false, ['verify']);
  if (!(await crypto.subtle.verify(algorithm, key, signature, signed))) throw bad;
  return claims.sub;
}

// ---------------------------------------------------------------- Firestore

// Flattens Firestore's typed values; only string fields are needed here.
const strings = (doc) =>
  Object.fromEntries(
    Object.entries(doc.fields || {}).map(([k, v]) => [k, v.stringValue]),
  );

async function getDoc(env, path, token) {
  const found = await getDocument(env, path, token);
  return found ? strings(found) : null;
}

async function getDocument(env, path, token) {
  const res = await fetch(`${firestoreBase(env)}/${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  // 403/404 both mean "no such record for this caller".
  if (res.status === 403 || res.status === 404) return null;
  if (!res.ok) throw new HttpError(503, 'Could not check your access. Try again.');
  return res.json();
}

async function findStudent(env, nsin) {
  const res = await fetch(`${firestoreBase(env)}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'students' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'nsin' },
            op: 'EQUAL',
            value: { stringValue: nsin },
          },
        },
        limit: 1,
      },
    }),
  });
  if (!res.ok) throw new HttpError(503, 'Could not check your access. Try again.');
  const row = (await res.json()).find((r) => r.document);
  return row ? strings(row.document) : null;
}

// ---------------------------------------------------------------- Access

/// Returns who the caller is, or throws. `admin` may act on any file.
async function authorize(request, env, subjectId) {
  const denied = new HttpError(403, 'You do not have access to this file.');
  const auth = request.headers.get('Authorization') || '';

  if (auth.startsWith('Bearer ')) {
    const token = auth.slice(7);
    const uid = await verifyIdToken(token, env.FIREBASE_PROJECT_ID);

    const staff = await getDoc(env, `staff/${uid}`, token);
    if (staff?.status === 'active' && ['principal', 'deputyPrincipal', 'registrar'].includes(staff.role)) {
      return { uid, admin: true };
    }
    const tutor = await getDoc(env, `tutors/${uid}`, token);
    if (tutor?.status === 'active') {
      const assigned = await getDoc(env, `tutor_assignments/${uid}_${subjectId}`, token);
      if (assigned) return { uid, admin: false };
    }
    throw denied;
  }

  const nsin = (request.headers.get('X-Student-NSIN') || '').trim().toUpperCase();
  if (nsin) {
    // Students may only read.
    if (request.method !== 'GET') throw denied;
    const student = await findStudent(env, nsin);
    if (student?.status !== 'active') throw denied;
    const subject = await getDoc(env, `subjects/${subjectId}`);
    if (!subject?.programType || subject.programType !== student.programType) throw denied;
    return { student: true };
  }

  throw new HttpError(401, 'Sign in to use files.');
}

// ---------------------------------------------------------------- Handlers

function parseKey(pathname) {
  if (!pathname.startsWith('/files/')) return null;
  let parts;
  try {
    parts = pathname.slice('/files/'.length).split('/').map(decodeURIComponent);
  } catch {
    return null;
  }
  const [root, subjectId, folder, name, ...rest] = parts;
  if (
    rest.length || root !== 'subjects' || folder !== 'content' ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(subjectId || '') ||
    !name || name === '.' || name === '..' || name.length > 200 ||
    /[\/\\\u0000-\u001f]/.test(name)
  ) return null;
  return { key: parts.join('/'), subjectId, name };
}

const json = (status, body) => Response.json(body, { status });

async function upload(request, env, { key, name }, caller) {
  const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : '';
  if (!Object.hasOwn(CONTENT_TYPES, ext)) {
    throw new HttpError(415, 'This file type is not supported.');
  }
  const length = Number(request.headers.get('Content-Length'));
  if (!request.body || !(length > 0)) throw new HttpError(411, 'The file is empty.');
  if (length > MAX_BYTES) throw new HttpError(413, 'The file is larger than 95 MB.');

  const stored = await env.BUCKET.put(key, request.body, {
    // Never overwrite: only write if nothing is at this key yet.
    onlyIf: new Headers({ 'If-None-Match': '*' }),
    httpMetadata: { contentType: CONTENT_TYPES[ext] },
    customMetadata: { uploadedBy: caller.uid },
  });
  if (!stored) throw new HttpError(409, 'A file with this name already exists.');
  return json(201, { key, size: stored.size });
}

async function download(env, { key, name }) {
  const object = await env.BUCKET.get(key);
  if (!object) throw new HttpError(404, 'File not found.');
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Content-Length', String(object.size));
  headers.set('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(name)}`);
  headers.set('Cache-Control', 'private, no-store');
  headers.set('X-Content-Type-Options', 'nosniff');
  return new Response(object.body, { headers });
}

async function remove(env, { key }, caller) {
  const object = await env.BUCKET.head(key);
  if (object) {
    if (!caller.admin && object.customMetadata?.uploadedBy !== caller.uid) {
      throw new HttpError(403, 'You can only delete files you uploaded.');
    }
    await env.BUCKET.delete(key);
  }
  return new Response(null, { status: 204 }); // already gone counts as deleted
}

// Browsers only: lets the listed website origins call this Worker.
function withCors(request, env, response) {
  const origin = request.headers.get('Origin');
  const allowed = (env.ALLOWED_ORIGINS || '').split(',').map((o) => o.trim());
  if (!origin || !allowed.includes(origin)) return response;
  const out = new Response(response.body, response);
  out.headers.set('Access-Control-Allow-Origin', origin);
  out.headers.set('Access-Control-Allow-Methods', 'GET, PUT, POST, DELETE, OPTIONS');
  out.headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Student-NSIN');
  out.headers.set('Access-Control-Max-Age', '86400');
  out.headers.append('Vary', 'Origin');
  return out;
}

async function handle(request, env) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204 });
  const { pathname } = new URL(request.url);
  if (pathname === '/fees') {
    if (request.method !== 'POST') throw new HttpError(405, 'Method not allowed.');
    return fees(request, env);
  }
  if (pathname === '/uhpab') {
    if (request.method !== 'POST') throw new HttpError(405, 'Method not allowed.');
    return uhpabResults(request, env, { findStudent });
  }
  if (pathname.startsWith('/files/uhpab/')) {
    return uhpabFile(request, env, pathname,
      { verifyIdToken, getDocument, findStudent, upload, download, remove });
  }
  if (pathname.startsWith('/files/public/')) {
    return publicFile(request, env, pathname, { verifyIdToken, getDocument, upload, download, remove });
  }
  const file = parseKey(pathname);
  if (!file) throw new HttpError(404, 'Not found.');
  if (!['GET', 'PUT', 'DELETE'].includes(request.method)) {
    throw new HttpError(405, 'Method not allowed.');
  }
  const caller = await authorize(request, env, file.subjectId);
  if (request.method === 'PUT') return upload(request, env, file, caller);
  if (request.method === 'DELETE') return remove(env, file, caller);
  return download(env, file);
}

export default {
  async fetch(request, env) {
    let response;
    try {
      response = await handle(request, env);
    } catch (e) {
      if (!(e instanceof HttpError)) console.error(e);
      response = json(e.status || 500, {
        error: e instanceof HttpError ? e.message : 'Something went wrong.',
      });
    }
    return withCors(request, env, response);
  },
};
