// Copies Firestore routes, votes, views and feedback into Supabase. Firestore is
// only read. It's safe to run twice, because rows with the same key are replaced.
//
// Usage (see README.md):
//   node tool/route_migration/migrate.js --target staging --dry-run
//   node tool/route_migration/migrate.js --target staging
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'transitph-75da4';
const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const LIVE_SUPABASE_REF = 'rruijvorkljjpfkbamls';
const CHUNK_SIZE = 100;
const PARALLEL_READS = 8;

// These have their own columns.
const COLUMN_FIELDS = [
  'views',
  'upvotes',
  'downvotes',
  'approvalStatus',
  'createdAt',
  'updatedAt',
  'feedbackSummary',
  'contributorId',
  'contributorName',
];

// Same order as RouteService._extractContributorIdentifier in the old app.
const OWNER_FIELDS = ['contributorId', 'userId', 'contributorEmail', 'userEmail', 'email'];

const SUMMARY_COUNTERS = [
  'fareAccurateYes',
  'fareAccurateNo',
  'scheduleAccurateYes',
  'scheduleAccurateNo',
  'stillOperatingYes',
  'stillOperatingNo',
];

const EMAIL = /[^\s@"]+@[^\s@"]+\.[^\s@"]+/;

function plain(value) {
  if (value === undefined || value === null) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('referenceValue' in value) return value.referenceValue;
  if ('geoPointValue' in value) return value.geoPointValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(plain);
  if ('mapValue' in value) {
    return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([k, v]) => [k, plain(v)]));
  }
  return null;
}

const fieldsOf = (doc) => plain({ mapValue: { fields: doc.fields ?? {} } });
const docIdOf = (doc) => doc.name.split('/').pop();

function ownerOf(fields) {
  for (const key of OWNER_FIELDS) {
    const value = fields[key];
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return null;
}

// Old routes can hold coordinates as text, and the app accepts that too.
function coordinate(value, limit) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  if (value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) && Math.abs(number) <= limit ? number : null;
}

// PostGIS wants longitude first, the opposite of how we write lat/lng. These
// match rows.ts in routes-api, so a route reads the same either way.
function lngLat(lat, lng) {
  const y = coordinate(lat, 90);
  const x = coordinate(lng, 180);
  return x === null || y === null ? null : `${x} ${y}`;
}

function point(lat, lng) {
  const position = lngLat(lat, lng);
  return position === null ? null : `SRID=4326;POINT(${position})`;
}

function line(pathPoints) {
  if (!Array.isArray(pathPoints)) return null;
  const positions = pathPoints.map((p) => lngLat(p?.lat, p?.lng)).filter((p) => p !== null);
  return positions.length < 2 ? null : `SRID=4326;LINESTRING(${positions.join(',')})`;
}

function count(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.trunc(number) : 0;
}

function statusOf(saved, problems) {
  if (saved === null || saved === undefined || saved === 'approved') return 'published';
  if (saved === 'pending' || saved === 'rejected') return saved;
  // Not something we know. Publishing it could show riders a bad route.
  problems.push('unknown_status');
  return 'pending';
}

// uidsByEmail has lowercase emails as keys.
function toRow(doc, uidsByEmail) {
  const id = docIdOf(doc);
  const fields = fieldsOf(doc);
  const problems = [];

  const status = statusOf(fields.approvalStatus, problems);
  const updatedAt = fields.updatedAt ?? null;

  let contributorId = ownerOf(fields);
  if (contributorId?.includes('@')) {
    const uid = uidsByEmail.get(contributorId.toLowerCase());
    if (!uid) problems.push('unresolved_owner');
    contributorId = uid ?? null;
  }

  // Published rows can be read with the public key, so no emails may stay here.
  const data = { ...fields };
  for (const key of [...COLUMN_FIELDS, ...OWNER_FIELDS]) delete data[key];
  if (fields.id !== undefined && fields.id !== id) problems.push('id_mismatch');
  data.id = id;
  if (EMAIL.test(JSON.stringify(data))) problems.push('email_in_data');

  const geom = line(fields.pathPoints);
  if (geom === null) problems.push('no_path');
  if (!fields.createdAt) problems.push('no_created_at');

  const row = {
    id,
    source: id.startsWith('osm-') ? 'osm' : 'rider',
    contributor_id: contributorId,
    contributor_name: typeof fields.contributorName === 'string' ? fields.contributorName : null,
    status,
    // A person approved these routes, so they count as verified.
    verification: status === 'published' ? 'verified' : 'unverified',
    correction_of: typeof fields.correctionOf === 'string' ? fields.correctionOf : null,
    data,
    geom,
    start_pt: point(fields.startLat, fields.startLng),
    end_pt: point(fields.endLat, fields.endLng),
    views: count(fields.views),
    upvotes: count(fields.upvotes),
    downvotes: count(fields.downvotes),
    feedback_summary: {
      ...Object.fromEntries(SUMMARY_COUNTERS.map((key) => [key, 0])),
      ...(fields.feedbackSummary ?? {}),
    },
    revision: 1,
    created_at: fields.createdAt ?? null,
    updated_at: updatedAt,
    published_at: status === 'published' ? updatedAt : null,
    rejected_at: status === 'rejected' ? updatedAt : null,
  };
  return { row, problems };
}

function toVoteRow(routeId, doc) {
  const fields = fieldsOf(doc);
  if (fields.vote !== 'up' && fields.vote !== 'down') return null;
  return {
    route_id: routeId,
    user_id: docIdOf(doc),
    vote: fields.vote,
    created_at: fields.createdAt ?? null,
    updated_at: fields.updatedAt ?? null,
  };
}

function toViewRow(routeId, doc) {
  return { route_id: routeId, user_id: docIdOf(doc), created_at: fieldsOf(doc).createdAt ?? null };
}

function toFeedbackRow(routeId, doc) {
  const fields = fieldsOf(doc);
  return {
    route_id: routeId,
    user_id: docIdOf(doc),
    fare_accurate: fields.fareAccurate ?? null,
    schedule_accurate: fields.scheduleAccurate ?? null,
    still_operating: fields.stillOperating ?? null,
    created_at: fields.createdAt ?? null,
    updated_at: fields.updatedAt ?? null,
  };
}

// Reading Firestore

function firebaseToken() {
  const file = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  return JSON.parse(fs.readFileSync(file, 'utf8')).tokens.access_token;
}

async function listDocs(token, collectionPath, mask = []) {
  const docs = [];
  const fields = mask.map((f) => `&mask.fieldPaths=${f}`).join('');
  let pageToken = '';
  do {
    const url = `${FIRESTORE}/${collectionPath}?pageSize=300${fields}${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (response.status === 401) throw new Error('Firebase login expired. Run: firebase projects:list');
    if (!response.ok) throw new Error(`Reading ${collectionPath}: ${response.status} ${(await response.text()).slice(0, 200)}`);
    const page = await response.json();
    docs.push(...(page.documents ?? []));
    pageToken = page.nextPageToken ?? '';
  } while (pageToken);
  return docs;
}

async function loadUidsByEmail(token) {
  const uids = new Map();
  for (const doc of await listDocs(token, 'users', ['email', 'uid'])) {
    const { email, uid } = fieldsOf(doc);
    if (typeof email === 'string' && email) uids.set(email.toLowerCase(), uid || docIdOf(doc));
  }
  return uids;
}

async function loadEngagement(token, routeDocs) {
  const rows = { votes: [], views: [], feedback: [], skippedVotes: 0 };
  let next = 0;
  async function worker() {
    while (next < routeDocs.length) {
      const doc = routeDocs[next++];
      const id = docIdOf(doc);
      const encoded = encodeURIComponent(id);
      const [votes, views, feedback] = await Promise.all([
        listDocs(token, `routes/${encoded}/routeVotes`),
        listDocs(token, `routes/${encoded}/routeViews`),
        listDocs(token, `routes/${encoded}/routeFeedback`),
      ]);
      for (const vote of votes) {
        const row = toVoteRow(id, vote);
        if (row) rows.votes.push(row);
        else rows.skippedVotes++;
      }
      rows.views.push(...views.map((view) => toViewRow(id, view)));
      rows.feedback.push(...feedback.map((item) => toFeedbackRow(id, item)));
    }
  }
  await Promise.all(Array.from({ length: PARALLEL_READS }, worker));
  return rows;
}

// Writing Supabase

function readEnvFile(file) {
  const env = {};
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const at = line.indexOf('=');
    if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return env;
}

// Staging comes from .env.staging. The live project needs its key typed into
// the shell plus a second flag, so it can't be reached by a slip.
function supabaseTarget(target, args) {
  if (target === 'staging') {
    const env = readEnvFile('.env.staging');
    if (env.SUPABASE_URL.includes(LIVE_SUPABASE_REF)) {
      throw new Error('.env.staging points at the live project. Stopping.');
    }
    return { url: env.SUPABASE_URL, key: env.SUPABASE_SERVICE_ROLE_KEY };
  }
  if (target === 'prod') {
    if (!args.includes('--i-mean-live')) throw new Error('--target prod also needs --i-mean-live.');
    const { SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: key } = process.env;
    if (!url || !key) throw new Error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in this shell first.');
    return { url, key };
  }
  throw new Error('Use --target staging or --target prod.');
}

async function upsert({ url, key }, table, conflictColumns, rows) {
  for (let start = 0; start < rows.length; start += CHUNK_SIZE) {
    const response = await fetch(`${url}/rest/v1/${table}?on_conflict=${conflictColumns}`, {
      method: 'POST',
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify(rows.slice(start, start + CHUNK_SIZE)),
    });
    if (!response.ok) throw new Error(`Writing ${table}: ${response.status} ${(await response.text()).slice(0, 300)}`);
  }
}

async function countRows({ url, key }, table) {
  const response = await fetch(`${url}/rest/v1/${table}?select=*&limit=1`, {
    headers: { apikey: key, Authorization: `Bearer ${key}`, Prefer: 'count=exact' },
  });
  return Number(response.headers.get('content-range')?.split('/')[1]);
}

async function main(args) {
  const target = args[args.indexOf('--target') + 1];
  const dryRun = args.includes('--dry-run');
  const supabase = supabaseTarget(target, args);
  const token = firebaseToken();

  console.log(`Reading Firestore${dryRun ? ' (dry run, nothing will be written)' : ''}...`);
  const routeDocs = await listDocs(token, 'routes');
  const uidsByEmail = await loadUidsByEmail(token);
  const converted = routeDocs.map((doc) => toRow(doc, uidsByEmail));
  const rows = converted.map((c) => c.row);
  const engagement = await loadEngagement(token, routeDocs);

  const tally = (values) => values.reduce((all, v) => ({ ...all, [v]: (all[v] ?? 0) + 1 }), {});
  console.log(`\nRoutes: ${rows.length}`);
  console.log('  by status:', JSON.stringify(tally(rows.map((r) => r.status))));
  console.log('  by source:', JSON.stringify(tally(rows.map((r) => r.source))));
  console.log(`  votes: ${engagement.votes.length} (skipped ${engagement.skippedVotes})`);
  console.log(`  views: ${engagement.views.length}`);
  console.log(`  feedback: ${engagement.feedback.length}`);

  console.log('\nThings to look at:');
  const problemNames = [...new Set(converted.flatMap((c) => c.problems))].sort();
  if (problemNames.length === 0) console.log('  none');
  for (const name of problemNames) {
    const affected = converted.filter((c) => c.problems.includes(name)).map((c) => c.row);
    console.log(`  ${name}: ${affected.length}`);
    for (const row of affected.slice(0, 40)) {
      console.log(`    [${row.status}] ${row.id}  ${row.data.startLocation ?? '?'} -> ${row.data.endLocation ?? '?'}`);
    }
  }

  if (dryRun) return;

  console.log(`\nWriting to ${target}...`);
  await upsert(supabase, 'transit_routes', 'id', rows);
  await upsert(supabase, 'route_votes', 'route_id,user_id', engagement.votes);
  await upsert(supabase, 'route_views', 'route_id,user_id', engagement.views);
  await upsert(supabase, 'route_quality_feedback', 'route_id,user_id', engagement.feedback);

  console.log('Rows now in Supabase:');
  for (const table of ['transit_routes', 'route_votes', 'route_views', 'route_quality_feedback']) {
    console.log(`  ${table}: ${await countRows(supabase, table)}`);
  }
}

module.exports = { plain, ownerOf, toRow, toVoteRow, toViewRow, toFeedbackRow };

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
