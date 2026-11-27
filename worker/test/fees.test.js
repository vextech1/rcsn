import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Miniflare, Response as MfResponse } from 'miniflare';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const value = (v) => Array.isArray(v) ? { arrayValue: { values: v.map(value) } }
  : typeof v === 'number' ? { integerValue: String(v) } : { stringValue: v };
const doc = (o, name = 'x') => ({
  name, fields: Object.fromEntries(Object.entries(o).map(([k, v]) => [k, value(v)])),
});

const NSIN = 'JAN26/U028/MCK/001';
const record = { paymentNumber: 'PN12345', nsin: NSIN, name: 'Mary Achieng',
  programType: 'certificateNursing', year: 1, semester: 1, tuition: 1000, paid: 400 };
const DOCS = {
  'fee_guardians/PN12345': { names: ['John Okot'] },
  'student_bio/JAN26_U028_MCK_001': { dateOfBirth: '2006-03-14', district: 'Gulu',
    village: 'Pece', primarySchool: 'Pece Primary School', secondarySchool: '' },
};
let attempts = {};

async function outbound(request) {
  const url = new URL(request.url);
  if (url.hostname === 'oauth2.googleapis.com') {
    return MfResponse.json({ access_token: 'svc', expires_in: 3600 });
  }
  assert.equal(request.headers.get('authorization'), 'Bearer svc');
  const path = decodeURIComponent(url.pathname.split('/documents')[1]);
  if (path === ':commit') {
    const t = (await request.json()).writes[0].transform;
    attempts[t.document] = (attempts[t.document] || 0) +
      Number(t.fieldTransforms[0].increment.integerValue);
    return MfResponse.json({ writeResults: [{ transformResults: [value(attempts[t.document])] }] });
  }
  if (path.endsWith(':runQuery')) {
    const q = (await request.json()).structuredQuery;
    if (q.from[0].collectionId === 'payments') {
      return MfResponse.json([{ document: doc({ amount: 400, method: 'bank', reference: 'R1' }) }]);
    }
    return MfResponse.json(q.where.fieldFilter.value.stringValue === 'PN12345'
      ? [{ document: doc(record, 'a/PN12345_Y1S1') }] : [{}]);
  }
  const found = DOCS[path.slice(1)];
  return found ? MfResponse.json(doc(found)) : new MfResponse('{}', { status: 404 });
}

let mf;
before(() => {
  mf = new Miniflare({
    modules: true,
    modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }],
    scriptPath: fileURLToPath(new URL('../src/index.js', import.meta.url)),
    compatibilityDate: '2026-08-01',
    bindings: {
      FIREBASE_PROJECT_ID: 'school-msa',
      FIREBASE_SERVICE_ACCOUNT: JSON.stringify({
        client_email: 'svc@example.com',
        private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
      }),
    },
    outboundService: outbound,
  });
});
after(() => mf.dispose());
beforeEach(() => { attempts = {}; });

const ask = async (body) => {
  const res = await fetch(new URL('/fees', await mf.ready), {
    method: 'POST', body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
};
const parent = (answers, guardian = 'okot  JOHN') => ({ code: 'pn12345', guardian, answers });
const good = { dateOfBirth: '2006-03-14', address: 'Pece, Gulu' };

describe('fee lookup', () => {
  it('accepts matching names and two answers, ignoring case and order', async () => {
    const res = await ask(parent(good));
    assert.equal(res.status, 200);
    assert.equal(res.body.records[0].paid, 400);
    assert.equal(res.body.records[0].payments[0].reference, 'R1');
  });
  it('rejects any wrong, missing or unrecorded answer', async () => {
    for (const body of [
      parent(good, 'Peter Okot'),
      parent({ ...good, dateOfBirth: '2006-03-15' }),
      parent({ studentName: 'Mary Achieng', secondarySchool: '' }),
      { ...parent(good), code: 'NOPE99' },
    ]) assert.equal((await ask(body)).status, 403);
  });
  it('needs exactly two answers', async () => {
    assert.equal((await ask(parent({ dateOfBirth: '2006-03-14' }))).status, 400);
    assert.equal((await ask(parent({ ...good, studentName: 'x' }))).status, 400);
  });
  it('lets a signed-in student use the code with their own NSIN only', async () => {
    assert.equal((await ask({ code: 'PN12345', nsin: NSIN })).status, 200);
    assert.equal((await ask({ code: 'PN12345', nsin: 'JAN26/U028/MCK/002' })).status, 403);
  });
  it('locks after five wrong attempts, but successes do not count', async () => {
    for (let i = 0; i < 8; i++) assert.equal((await ask(parent(good))).status, 200);
    for (let i = 0; i < 5; i++) assert.equal((await ask(parent(good, 'No One'))).status, 403);
    assert.equal((await ask(parent(good))).status, 429);
  });
});
