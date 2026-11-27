// Files attached to Public Space posts: /files/public/{uid}/{postId}/{name}.
//
// Staff and active tutors upload under their own uid, before the post exists.
// A file can be read by whoever may read the post that lists it: everyone once
// it is published, only its author and moderators before that.

import { HttpError } from './common.js';

const POSTERS = ['principal', 'deputyPrincipal', 'registrar', 'bursar'];
const MODERATORS = ['principal', 'deputyPrincipal', 'registrar'];

function parse(pathname) {
  let parts;
  try {
    parts = pathname.slice('/files/'.length).split('/').map(decodeURIComponent);
  } catch {
    return null;
  }
  const [, owner, postId, name, ...rest] = parts;
  const id = /^[A-Za-z0-9_-]{1,128}$/;
  if (
    rest.length || !id.test(owner || '') || !id.test(postId || '') ||
    !name || name === '.' || name === '..' || name.length > 200 ||
    /[\/\\\u0000-\u001f]/.test(name)
  ) return null;
  return { key: parts.join('/'), owner, postId, name };
}

export async function publicFile(request, env, pathname, tools) {
  const file = parse(pathname);
  if (!file) throw new HttpError(404, 'Not found.');
  if (!['GET', 'PUT', 'DELETE'].includes(request.method)) {
    throw new HttpError(405, 'Method not allowed.');
  }
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  const uid = token ? await tools.verifyIdToken(token, env.FIREBASE_PROJECT_ID) : null;
  const post = () => tools.getDocument(env, `public_posts/${file.postId}`, token);

  if (request.method === 'GET') {
    const fields = (await post())?.fields;
    const listed = fields?.attachments?.arrayValue?.values || [];
    if (
      fields?.authorId?.stringValue !== file.owner ||
      !listed.some((v) => v.stringValue === file.name)
    ) throw new HttpError(404, 'File not found.');
    const response = await tools.download(env, file);
    // Pictures are shown inside the app; unpublished ones must not be cached.
    if (fields.status?.stringValue === 'published') {
      response.headers.set('Cache-Control', 'public, max-age=3600');
    }
    return response;
  }

  if (!uid) throw new HttpError(401, 'Sign in to use files.');
  const record = async (path) => {
    const fields = (await tools.getDocument(env, path, token))?.fields;
    return fields?.status?.stringValue === 'active' ? fields : null;
  };
  const staff = await record(`staff/${uid}`);
  const role = staff?.role?.stringValue;
  const denied = new HttpError(403, 'You do not have access to this file.');

  if (request.method === 'DELETE') {
    const admin = MODERATORS.includes(role);
    if (!admin && uid !== file.owner) throw denied;
    return tools.remove(env, file, { uid, admin });
  }

  if (uid !== file.owner) throw denied;
  if (!POSTERS.includes(role) && !(await record(`tutors/${uid}`))) throw denied;
  // Otherwise an approved file could be deleted and replaced with another.
  if (await post()) throw new HttpError(409, 'Files cannot be added to an existing post.');
  return tools.upload(request, env, file, { uid });
}
