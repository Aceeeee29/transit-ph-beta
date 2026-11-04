// Step 3: reads the `routes` collection (lines and status only) to a JSON file.
// Read-only. Usage: node read_routes.js <out.json>
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'transitph-75da4';
const cfg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json'), 'utf8'));
const token = cfg.tokens.access_token;

const num = (v) => (v?.doubleValue ?? (v?.integerValue != null ? Number(v.integerValue) : null));
const str = (v) => v?.stringValue ?? null;

(async () => {
  const out = [];
  let pageToken = '';
  const mask = ['id', 'approvalStatus', 'startLocation', 'endLocation', 'contributorId', 'pathPoints', 'source']
    .map((f) => `mask.fieldPaths=${f}`).join('&');
  do {
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/routes?pageSize=300&${mask}${pageToken ? `&pageToken=${pageToken}` : ''}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`${res.status} ${(await res.text()).slice(0, 200)}`);
    const data = await res.json();
    for (const d of data.documents || []) {
      const f = d.fields || {};
      out.push({
        docId: d.name.split('/').pop(),
        status: str(f.approvalStatus) || 'approved',
        start: str(f.startLocation), end: str(f.endLocation),
        contributorId: str(f.contributorId),
        hasSource: !!f.source,
        path: (f.pathPoints?.arrayValue?.values || []).map((p) => ({
          lat: num(p.mapValue.fields.lat), lon: num(p.mapValue.fields.lng),
        })),
      });
    }
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  fs.writeFileSync(process.argv[2], JSON.stringify(out));
  const by = out.reduce((m, r) => ((m[r.status] = (m[r.status] || 0) + 1), m), {});
  console.log(`routes: ${out.length} ${JSON.stringify(by)}; osm imports: ${out.filter((r) => r.docId.startsWith('osm-')).map((r) => r.docId).join(', ')}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
