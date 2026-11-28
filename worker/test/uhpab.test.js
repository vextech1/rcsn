import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Miniflare, Response as MfResponse } from 'miniflare';

const PROJECT = 'school-msa';
const signing = generateKeyPairSync('rsa', { modulusLength: 2048 });
const service = generateKeyPairSync('rsa', { modulusLength: 2048 });
const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token(sub) {
  const now = Math.floor(Date.now() / 1000);
  const body = `${enc({ alg: 'RS256', kid: 'k1' })}.${enc({
    sub, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: now, exp: now + 3600,
  })}`;
  return `${body}.${createSign('RSA-SHA256').update(body).sign(signing.privateKey).toString('base64url')}`;
}

const value = (v) => typeof v === 'number' ? { integerValue: String(v) }
  : typeof v === 'boolean' ? { booleanValue: v }
  : typeof v === 'object' ? { mapValue: { fields: encodeFields(v) } }
  : { stringValue: v };
const encodeFields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, value(v)]));
const doc = (o, name = 'x') => ({ name, fields: encodeFields(o) });

const NSIN = 'JAN26/U028/CCN/001';
const KEY = 'JAN26_U028_CCN_001';
const unit = (mark, published) =>
  ({ subjectName: 'CN 111 Anatomy', year: 1, semester: 1, mark, published });
let docs;
let fees;

async function outbound(request) {
  const url = new URL(request.url);
  if (url.hostname === 'www.googleapis.com') {
    return MfResponse.json({ keys: [{ ...signing.publicKey.export({ format: 'jwk' }), kid: 'k1' }] });
  }
  if (url.hostname === 'oauth2.googleapis.com') {
    return MfResponse.json({ access_token: 'svc', expires_in: 3600 });
  }
  const path = decodeURIComponent(url.pathname.split('/documents')[1]);
  if (path === ':runQuery') {
    const q = (await request.json()).structuredQuery;
    const wanted = q.where.fieldFilter.value.stringValue;
    if (q.from[0].collectionId === 'students') {
      return MfResponse.json(wanted === NSIN || wanted === 'GONE/1'
        ? [{ document: doc({ nsin: wanted, status: wanted === NSIN ? 'active' : 'terminated' }) }] : [{}]);
    }
    assert.equal(request.headers.get('authorization'), 'Bearer svc');
    return MfResponse.json(wanted === NSIN && fees.length
      ? fees.map((f) => ({ document: doc({ nsin: NSIN, ...f }) })) : [{}]);
  }
  // Private records are read with the service account only.
  if (!path.startsWith('/staff/')) {
    assert.equal(request.headers.get('authorization'), 'Bearer svc');
  }
  const found = docs[path.slice(1)];
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
    bindings: {
      FIREBASE_PROJECT_ID: PROJECT,
      FIREBASE_SERVICE_ACCOUNT: JSON.stringify({
        client_email: 'svc@example.com',
        private_key: service.privateKey.export({ type: 'pkcs8', format: 'pem' }),
      }),
    },
    outboundService: outbound,
  });
});
after(() => mf.dispose());
beforeEach(() => {
  fees = [{ tuition: 1000000, paid: 1000000 }];
  docs = {
    'staff/reg': { role: 'registrar', status: 'active' },
    'staff/boss': { role: 'principal', status: 'active' },
    'staff/money': { role: 'bursar', status: 'active' },
    [`uhpab_results/${KEY}`]: {
      units: { s1: unit(45, true), s2: unit(80, false) },
      documents: {
        d1: { name: 'slip.pdf', title: 'Slip', published: true },
        d2: { name: 'draft.pdf', title: 'Draft', published: false },
      },
    },
  };
});

const results = async (nsin = NSIN) => {
  const res = await fetch(new URL('/uhpab', await mf.ready), {
    method: 'POST', body: JSON.stringify({ nsin }),
  });
  return { status: res.status, body: await res.json() };
};
const file = async (method, path, { uid, nsin, body } = {}) => {
  const headers = {};
  if (uid) headers.Authorization = `Bearer ${token(uid)}`;
  if (nsin) headers['X-Student-NSIN'] = nsin;
  const res = await fetch(new URL(`/files/uhpab/${path}`, await mf.ready), { method, body, headers });
  await res.arrayBuffer();
  return res.status;
};

describe('UHPAB results', () => {
  it('sends only published results to a student whose fees are cleared', async () => {
    const res = await results(NSIN.toLowerCase());
    assert.equal(res.status, 200);
    assert.equal(res.body.blocked, false);
    assert.deepEqual(res.body.units.map((u) => [u.subjectId, u.mark]), [['s1', 45]]);
    assert.deepEqual(res.body.documents.map((d) => d.id), ['d1']);
  });

  it('blocks for any balance, an unpriced record or no record, and sends nothing', async () => {
    for (const records of [
      [{ tuition: 1000000, paid: 999000 }],
      [{ tuition: 1000, paid: 1000 }, { tuition: 1000, paid: 0 }],
      [{ tuition: 0, paid: 0 }],
      [],
    ]) {
      fees = records;
      const res = await results();
      assert.deepEqual(res.body, { blocked: true, units: [], documents: [] });
    }
  });

  it('opens a blocked student only when the Bursar allows it', async () => {
    fees = [];
    docs[`result_clearance/${KEY}`] = { allowed: false };
    assert.equal((await results()).body.blocked, true);
    docs[`result_clearance/${KEY}`] = { allowed: true };
    assert.equal((await results()).body.blocked, false);
  });

  it('refuses unknown and terminated students', async () => {
    assert.equal((await results('NOBODY/1')).status, 403);
    assert.equal((await results('GONE/1')).status, 403);
    assert.equal((await results('')).status, 400);
  });

  it('lets only the registrar upload and delete', async () => {
    const path = `${KEY}/d1/slip.pdf`;
    assert.equal(await file('PUT', path, { uid: 'boss', body: 'x' }), 403);
    assert.equal(await file('PUT', path, { uid: 'money', body: 'x' }), 403);
    assert.equal(await file('PUT', path, { nsin: NSIN, body: 'x' }), 403);
    assert.equal(await file('PUT', path, { body: 'x' }), 401);
    assert.equal(await file('PUT', path, { uid: 'reg', body: 'x' }), 201);
    assert.equal(await file('GET', path, { uid: 'boss' }), 200);
    assert.equal(await file('GET', path, { uid: 'money' }), 403);
    assert.equal(await file('DELETE', path, { uid: 'boss' }), 403);
    assert.equal(await file('DELETE', path, { uid: 'reg' }), 204);
  });

  it('applies publishing and the fee block to downloads', async () => {
    await file('PUT', `${KEY}/d1/slip.pdf`, { uid: 'reg', body: 'x' });
    await file('PUT', `${KEY}/d2/draft.pdf`, { uid: 'reg', body: 'x' });
    assert.equal(await file('GET', `${KEY}/d1/slip.pdf`, { nsin: NSIN }), 200);
    assert.equal(await file('GET', `${KEY}/d2/draft.pdf`, { nsin: NSIN }), 404);
    assert.equal(await file('GET', `${KEY}/d1/slip.pdf`, { nsin: 'GONE/1' }), 403);
    fees = [{ tuition: 1000, paid: 0 }];
    assert.equal(await file('GET', `${KEY}/d1/slip.pdf`, { nsin: NSIN }), 403);
  });
});
