// Runs the Worker in the real Workers runtime (Miniflare) with a simulated R2
// bucket. Google's key endpoint and Firestore are faked.
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Miniflare, Response as MfResponse } from 'miniflare';

const PROJECT = 'school-msa';
const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const other = generateKeyPairSync('rsa', { modulusLength: 2048 });

const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token(sub, claims = {}, key = privateKey) {
  const now = Math.floor(Date.now() / 1000);
  const body = `${enc({ alg: 'RS256', kid: 'k1' })}.${enc({
    sub, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: now, exp: now + 3600, ...claims,
  })}`;
  return `${body}.${createSign('RSA-SHA256').update(body).sign(key).toString('base64url')}`;
}

const doc = (o) => ({
  fields: Object.fromEntries(Object.entries(o).map(([k, v]) => [k, { stringValue: v }])),
});
const DOCS = {
  'staff/boss': { role: 'principal', status: 'active' },
  'staff/money': { role: 'bursar', status: 'active' },
  'tutors/t1': { status: 'active' },
  'tutors/t2': { status: 'active' },
  'tutors/t3': { status: 'suspended' },
  'tutor_assignments/t1_anatomy': { tutorId: 't1' },
  'tutor_assignments/t2_anatomy': { tutorId: 't2' },
  'tutor_assignments/t3_anatomy': { tutorId: 't3' },
  'subjects/anatomy': { programType: 'certificateNursing' },
};
const STUDENTS = {
  'JAN26/U028/MCK/001': { status: 'active', programType: 'certificateNursing' },
  'JAN26/U028/MCK/003': { status: 'active', programType: 'certificateMidwifery' },
  'JAN26/U028/MCK/005': { status: 'suspended', programType: 'certificateNursing' },
};

async function outbound(request) {
  const url = new URL(request.url);
  if (url.hostname === 'www.googleapis.com') {
    return MfResponse.json({ keys: [{ ...publicKey.export({ format: 'jwk' }), kid: 'k1' }] });
  }
  if (url.pathname.endsWith(':runQuery')) {
    const nsin = (await request.json()).structuredQuery.where.fieldFilter.value.stringValue;
    return MfResponse.json(STUDENTS[nsin] ? [{ document: doc(STUDENTS[nsin]) }] : [{}]);
  }
  const found = DOCS[url.pathname.split('/documents/')[1]];
  return found ? MfResponse.json(doc(found)) : new MfResponse('{}', { status: 404 });
}

let mf;
before(() => {
  mf = new Miniflare({
    modules: true,
    modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }],
    scriptPath: fileURLToPath(new URL('../src/index.js', import.meta.url)),
    compatibilityDate: '2026-08-01',
    r2Buckets: ['BUCKET'],
    bindings: { FIREBASE_PROJECT_ID: PROJECT, ALLOWED_ORIGINS: 'https://site.example' },
    outboundService: outbound,
  });
});
after(() => mf.dispose());

// Real HTTP (not dispatchFetch) so Content-Length arrives as it would in production.
const send = async (pathname, init) => fetch(new URL(pathname, await mf.ready), init);
const path = (name, subject = 'anatomy') =>
  `/files/subjects/${subject}/content/${encodeURIComponent(name)}`;
const as = (uid) => ({ Authorization: `Bearer ${token(uid)}` });
const nsin = (n) => ({ 'X-Student-NSIN': `JAN26/U028/MCK/${n}` });
const call = (method, name, headers = {}, body, subject) =>
  send(path(name, subject), { method, headers, body });
const status = async (...args) => {
  const res = await call(...args);
  await res.arrayBuffer();
  return res.status;
};

describe('upload', () => {
  it('lets an assigned tutor upload, and never overwrite', async () => {
    assert.equal(await status('PUT', '1_Week 3 notes.pdf', as('t1'), 'hello'), 201);
    assert.equal(await status('PUT', '1_Week 3 notes.pdf', as('t2'), 'replaced'), 409);
    const res = await call('GET', '1_Week 3 notes.pdf', as('t1'));
    assert.equal(await res.text(), 'hello');
    assert.equal(res.headers.get('content-type'), 'application/pdf');
  });
  it('lets the principal upload', async () => {
    assert.equal(await status('PUT', 'a.docx', as('boss'), 'x'), 201);
  });
  it('refuses everyone else', async () => {
    assert.equal(await status('PUT', 'b.pdf', {}, 'x'), 401);
    assert.equal(await status('PUT', 'b.pdf', as('stranger'), 'x'), 403);
    assert.equal(await status('PUT', 'b.pdf', as('money'), 'x'), 403);
    assert.equal(await status('PUT', 'b.pdf', as('t3'), 'x'), 403);
    assert.equal(await status('PUT', 'b.pdf', as('t1'), 'x', 'other-subject'), 403);
    assert.equal(await status('PUT', 'b.pdf', nsin('001'), 'x'), 403);
  });
  it('refuses other file types and empty files', async () => {
    for (const name of ['v.mp4', 'p.exe', 'noext', 'x.constructor']) {
      assert.equal(await status('PUT', name, as('t1'), 'x'), 415, name);
    }
    assert.equal(await status('PUT', 'e.pdf', as('t1'), ''), 411);
  });
  it('refuses files over the limit', async () => {
    const big = new Uint8Array(95 * 1024 * 1024 + 1);
    assert.equal(await status('PUT', 'big.pdf', as('t1'), big), 413);
  });
});

describe('sign-in tokens', () => {
  const bearer = (t) => ({ Authorization: `Bearer ${t}` });
  it('rejects forged, expired and foreign tokens', async () => {
    for (const bad of [
      'junk',
      token('boss', {}, other.privateKey),
      token('boss', { exp: 1 }),
      token('boss', { aud: 'another-project' }),
      token('boss', { iss: 'https://evil.example' }),
    ]) assert.equal(await status('GET', 'a.docx', bearer(bad)), 401);
  });
});

describe('student download', () => {
  it('allows an active student of the same programme', async () => {
    assert.equal(await status('GET', 'a.docx', nsin('001')), 200);
  });
  it('refuses unknown, suspended and other-programme students', async () => {
    for (const n of ['999', '005', '003']) {
      assert.equal(await status('GET', 'a.docx', nsin(n)), 403, n);
    }
  });
  it('refuses deletes', async () => {
    assert.equal(await status('DELETE', 'a.docx', nsin('001')), 403);
  });
});

describe('delete', () => {
  it('only the uploader or an admin may delete', async () => {
    assert.equal(await status('PUT', 'd.pdf', as('t1'), 'x'), 201);
    assert.equal(await status('DELETE', 'd.pdf', as('t2')), 403);
    assert.equal(await status('DELETE', 'd.pdf', as('t1')), 204);
    assert.equal(await status('GET', 'd.pdf', as('t1')), 404);
    assert.equal(await status('DELETE', 'd.pdf', as('t1')), 204);
    assert.equal(await status('DELETE', 'a.docx', as('boss')), 204);
  });
});

describe('paths and CORS', () => {
  it('only serves subject content paths', async () => {
    for (const p of ['/', '/files/secret.pdf', '/files/subjects/a/content/x/y.pdf',
      '/files/subjects/a/content/%2F.pdf']) {
      const res = await send(p, { headers: as('boss') });
      assert.equal(res.status, 404, p);
    }
  });
  it('allows only listed website origins', async () => {
    const ask = (origin) => call('OPTIONS', 'a.pdf', { Origin: origin });
    assert.equal((await ask('https://site.example')).headers.get('access-control-allow-origin'), 'https://site.example');
    assert.equal((await ask('https://evil.example')).headers.get('access-control-allow-origin'), null);
  });
});
