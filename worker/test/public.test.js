import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Miniflare, Response as MfResponse } from 'miniflare';

const PROJECT = 'school-msa';
const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token(sub) {
  const now = Math.floor(Date.now() / 1000);
  const body = `${enc({ alg: 'RS256', kid: 'k1' })}.${enc({
    sub, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: now, exp: now + 3600,
  })}`;
  return `${body}.${createSign('RSA-SHA256').update(body).sign(privateKey).toString('base64url')}`;
}

const doc = (o) => ({
  fields: Object.fromEntries(Object.entries(o).map(([k, v]) => [k, Array.isArray(v)
    ? { arrayValue: { values: v.map((s) => ({ stringValue: s })) } }
    : { stringValue: v }])),
});
const DOCS = {
  'staff/money': { role: 'bursar', status: 'active' },
  'staff/boss': { role: 'deputyPrincipal', status: 'active' },
  'staff/guard': { role: 'staffMember', status: 'active' },
  'tutors/t1': { status: 'active' },
  'tutors/t3': { status: 'suspended' },
};

// Like the Firestore rules: published posts are open, others only to the
// author or a moderator; a missing post is refused.
async function outbound(request) {
  const url = new URL(request.url);
  if (url.hostname === 'www.googleapis.com') {
    return MfResponse.json({ keys: [{ ...publicKey.export({ format: 'jwk' }), kid: 'k1' }] });
  }
  const path = url.pathname.split('/documents/')[1];
  const found = DOCS[path];
  const auth = request.headers.get('authorization');
  const uid = auth && JSON.parse(Buffer.from(auth.split('.')[1], 'base64url')).sub;
  const hidden = path.startsWith('public_posts/') &&
    (!found || (found.status !== 'published' && ![found.authorId, 'boss'].includes(uid)));
  if (hidden) return new MfResponse('{}', { status: 403 });
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
    bindings: { FIREBASE_PROJECT_ID: PROJECT },
    outboundService: outbound,
  });
});
after(() => mf.dispose());

const status = async (method, path, uid, body) => {
  const res = await fetch(new URL(`/files/public/${path}`, await mf.ready), {
    method, body, headers: uid ? { Authorization: `Bearer ${token(uid)}` } : {},
  });
  await res.arrayBuffer();
  return res.status;
};

describe('public post files', () => {
  it('lets posting staff and active tutors upload under their own id', async () => {
    assert.equal(await status('PUT', 'money/p1/a.jpg', 'money', 'x'), 201);
    assert.equal(await status('PUT', 't1/p2/b.pdf', 't1', 'x'), 201);
    assert.equal(await status('PUT', 't1/p2/c.pdf', 'money', 'x'), 403);
    assert.equal(await status('PUT', 'guard/p3/a.jpg', 'guard', 'x'), 403);
    assert.equal(await status('PUT', 't3/p3/a.jpg', 't3', 'x'), 403);
    assert.equal(await status('PUT', 'x/p3/a.jpg', null, 'x'), 401);
    assert.equal(await status('PUT', 'money/p1/v.mp4', 'money', 'x'), 415);
  });
  it('shows a file only through a post that lists it', async () => {
    assert.equal(await status('GET', 'money/p1/a.jpg'), 404);
    DOCS['public_posts/p1'] = { authorId: 'money', status: 'published', attachments: ['a.jpg'] };
    DOCS['public_posts/p2'] = { authorId: 't1', status: 'pending', attachments: ['b.pdf'] };
    assert.equal(await status('GET', 'money/p1/a.jpg'), 200);
    assert.equal(await status('GET', 't1/p2/b.pdf'), 404);
    assert.equal(await status('GET', 't1/p2/b.pdf', 't1'), 200);
    assert.equal(await status('GET', 't1/p2/b.pdf', 'boss'), 200);
    assert.equal(await status('GET', 't1/p1/a.jpg'), 404);
  });
  it('never lets a posted file be replaced', async () => {
    assert.equal(await status('DELETE', 't1/p2/b.pdf', 'money'), 403);
    assert.equal(await status('DELETE', 't1/p2/b.pdf', 't1'), 204);
    assert.equal(await status('PUT', 't1/p2/b.pdf', 't1', 'new'), 409);
    assert.equal(await status('DELETE', 'money/p1/a.jpg', 'boss'), 204);
  });
});
