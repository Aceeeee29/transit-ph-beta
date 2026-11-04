// Step 5: saves the chosen OSM routes to Firestore `routes` as pending, each with
// an auditLogs/created entry, in one all-or-nothing commit that refuses to
// overwrite an existing document.
// Usage: node write.js <docs.json> <minCamanavaKm> <maxKm>   (e.g. 3 50)
const fs = require('fs');
const os = require('os');
const path = require('path');

const [, , docsFile, minIn, maxLen] = process.argv;
const PROJECT = 'transitph-75da4';
const DB = `projects/${PROJECT}/databases/(default)/documents`;
const token = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json'), 'utf8')).tokens.access_token;

function value(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: v.length ? { values: v.map(value) } : {} };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)])) } };
}
// Coordinates must stay doubles even when they happen to be whole numbers.
const doubleKeys = new Set(['lat', 'lng', 'startLat', 'startLng', 'endLat', 'endLng']);
function fields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) out[k] = doubleKeys.has(k) && typeof v === 'number' ? { doubleValue: v } : value(v);
  return out;
}

(async () => {
  const docs = JSON.parse(fs.readFileSync(docsFile, 'utf8'))
    .filter((d) => d.preview.camanavaKm >= +minIn && d.preview.km <= +maxLen);
  const writes = [];
  for (const d of docs) {
    writes.push({
      update: { name: `${DB}/routes/${d.id}`, fields: fields(d.fields) },
      currentDocument: { exists: false },
      updateTransforms: [
        { fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' },
        { fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' },
      ],
    });
    writes.push({
      update: {
        name: `${DB}/routes/${d.id}/auditLogs/created`,
        fields: fields({
          routeId: d.id,
          action: 'route_created',
          actorId: d.fields.contributorId,
          meta: { source: 'openstreetmap', relationId: d.fields.source.relationId },
        }),
      },
      currentDocument: { exists: false },
      updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
    });
  }
  const res = await fetch(`https://firestore.googleapis.com/v1/${DB}:commit`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes }),
  });
  const text = await res.text();
  if (!res.ok) { console.error(`commit failed: ${res.status} ${text.slice(0, 400)}`); process.exit(1); }
  console.log(`saved ${docs.length} routes (${writes.length} documents) as pending:`);
  for (const d of docs) console.log(` ${d.id}  ${d.preview.mode} [${d.preview.ref || '-'}] ${d.preview.name}`);
})().catch((e) => { console.error(e); process.exit(1); });
