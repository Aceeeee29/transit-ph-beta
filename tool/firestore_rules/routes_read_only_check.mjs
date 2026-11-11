// Checks that firestore.rules keeps the old Firestore routes read-only.
//
// Routes moved to Supabase, so nobody, staff included, may write to
// routes or its subcollections any more. Reads stay open so older app
// versions still show routes until they update.
//
// Runs against the local emulator only, never the real project:
//   npx firebase emulators:exec --only firestore --project demo-transitph \
//     "node tool/firestore_rules/routes_read_only_check.mjs"
//
// No packages needed. The emulator accepts unsigned test tokens, and
// "Bearer owner" skips the rules so the script can add test data.

const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host) {
  console.error('Run this inside "firebase emulators:exec" (no emulator found).');
  process.exit(1);
}
const project = 'demo-transitph';
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;

// An unsigned sign-in token for a test account.
function tokenFor(uid) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    iss: `https://securetoken.google.com/${project}`,
    aud: project,
    sub: uid,
    user_id: uid,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    firebase: { sign_in_provider: 'password' },
  })}.`;
}

function toValue(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === 'number') return { doubleValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  return { stringValue: String(value) };
}

const toFields = (data) =>
  Object.fromEntries(Object.entries(data).map(([key, value]) => [key, toValue(value)]));

async function send(who, method, path, data, mask) {
  const headers = { 'Content-Type': 'application/json' };
  if (who === 'owner') headers.Authorization = 'Bearer owner';
  else if (who) headers.Authorization = `Bearer ${tokenFor(who)}`;
  let url = `${base}/${path}`;
  if (mask) url += '?' + mask.map((field) => `updateMask.fieldPaths=${field}`).join('&');
  const response = await fetch(url, {
    method,
    headers,
    body: data ? JSON.stringify({ fields: toFields(data) }) : undefined,
  });
  return response.status;
}

// Adds a document as the emulator owner, skipping the rules.
async function seed(path, data) {
  const status = await send('owner', 'PATCH', path, data);
  if (status !== 200) throw new Error(`seed ${path} failed: ${status}`);
}

const read = (who, path) => send(who, 'GET', path);
const create = (who, collection, id, data) =>
  send(who, 'POST', `${collection}?documentId=${id}`, data);
const update = (who, path, data) => send(who, 'PATCH', path, data, Object.keys(data));
const remove = (who, path) => send(who, 'DELETE', path);

async function groupRead(who, collectionId) {
  const response = await fetch(`${base}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tokenFor(who)}` },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId, allDescendants: true }] } }),
  });
  return response.status;
}

let failures = 0;
async function expectStatus(label, allowed, attempt) {
  const status = await attempt;
  const ok = allowed ? status === 200 : status === 403;
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label} (${status}, expected ${allowed ? 'allowed' : 'denied'})`);
}

await seed('users/rider', { role: 'user', name: 'Rider' });
await seed('users/mod', { role: 'moderator', name: 'Mod' });
await seed('users/admin', { role: 'superadmin', name: 'Admin' });
await seed('routes/live', {
  contributorId: 'rider', approvalStatus: 'approved', views: 1, upvotes: 0, downvotes: 0,
});
await seed('routes/waiting', { contributorId: 'rider', approvalStatus: 'pending' });
await seed('routes/live/routeVotes/rider', { vote: 'up' });
await seed('routes/live/routeViews/rider', { viewedAt: new Date() });
await seed('routes/live/routeFeedback/rider', { routeId: 'live', userId: 'rider' });
await seed('routes/live/auditLogs/log1', { action: 'approved', actorId: 'mod' });

const pending = { contributorId: 'rider', approvalStatus: 'pending', name: 'New' };

// Reads still work, so older app versions keep showing routes.
await expectStatus('rider reads a route', true, read('rider', 'routes/live'));
await expectStatus('signed-out reads a route', false, read(null, 'routes/live'));

// Nobody adds, edits or removes routes here any more.
await expectStatus('rider adds a route', false, create('rider', 'routes', 'new1', pending));
await expectStatus('moderator adds a route', false, create('mod', 'routes', 'new2', pending));
await expectStatus('superadmin adds a route', false, create('admin', 'routes', 'new3', pending));
await expectStatus('rider edits own route', false, update('rider', 'routes/live', { name: 'X' }));
await expectStatus('rider counts a view', false, update('rider', 'routes/live', { views: 2 }));
await expectStatus('moderator approves', false,
  update('mod', 'routes/waiting', { approvalStatus: 'approved' }));
await expectStatus('superadmin edits', false, update('admin', 'routes/live', { name: 'X' }));
await expectStatus('rider hands route over on account close', false,
  update('rider', 'routes/live', {
    contributorId: null, contributorName: 'Former rider', contributorClosed: true,
  }));
await expectStatus('rider removes own pending route', false, remove('rider', 'routes/waiting'));
await expectStatus('superadmin removes a route', false, remove('admin', 'routes/live'));

// Old markers: the rider reads their own, nobody writes.
for (const sub of ['routeVotes', 'routeViews', 'routeFeedback']) {
  const own = `routes/live/${sub}/rider`;
  await expectStatus(`rider reads own ${sub}`, true, read('rider', own));
  await expectStatus(`someone else reads the rider's ${sub}`, false, read('mod', own));
  await expectStatus(`rider edits own ${sub}`, false, update('rider', own, { x: 1 }));
  await expectStatus(`rider adds own ${sub}`, false,
    create('rider', `routes/waiting/${sub}`, 'rider', { x: 1 }));
  await expectStatus(`rider removes own ${sub}`, false, remove('rider', own));
}

// Old moderation history: staff read it (the dashboard counts approvals).
await expectStatus('moderator reads audit log', true, read('mod', 'routes/live/auditLogs/log1'));
await expectStatus('rider reads audit log', false, read('rider', 'routes/live/auditLogs/log1'));
await expectStatus('superadmin reads all audit logs', true, groupRead('admin', 'auditLogs'));
await expectStatus('rider adds feedback log', false,
  create('rider', 'routes/live/auditLogs', 'log2', {
    action: 'commuter_feedback_submitted', actorId: 'rider',
  }));
await expectStatus('moderator adds audit log', false,
  create('mod', 'routes/live/auditLogs', 'log3', { action: 'approved', actorId: 'mod' }));

// The rest of the rules still work (this file doesn't just deny everything).
await expectStatus('rider still adds a post', true, create('rider', 'posts', 'p1', {
  userId: 'rider', content: 'Hello', moderationStatus: 'approved',
}));

console.log(failures ? `\n${failures} check(s) failed` : '\nAll checks passed');
process.exit(failures ? 1 : 0);
