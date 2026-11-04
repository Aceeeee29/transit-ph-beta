// Step 4: turns OSM candidates into TransitPH route documents (preview only).
// Usage: node prepare.js <candidates.json> <existing_routes.json> <out dir> <routes_meta.json>
// Keeps routes that really serve CAMANAVA, drops ones moderators already
// rejected and ones that repeat an existing route or another candidate,
// then writes docs.json (what would be saved) and preview.md. Saves nothing
// to Firestore.
const fs = require('fs');
const path = require('path');

const [, , candFile, existingFile, outDir, metaFile] = process.argv;
const tagsById = new Map(
  JSON.parse(fs.readFileSync(metaFile, 'utf8')).elements.map((e) => [e.id, e.tags || {}]),
);

// "Serves CAMANAVA" (chosen 2026-11-04): at least this much of the line
// inside the four cities, and not a long provincial run.
const MIN_CAMANAVA_KM = 3;
const MAX_ROUTE_KM = 50;

// OSM routes a moderator rejected and deleted (2026-10-19). Never offer
// them again; add to this list when moderators reject more.
const REJECTED_BEFORE = new Set([
  11246063, 11246064, 14878114, 15093994, 15093995, 15093996, 15093997,
]);

const candidates = JSON.parse(fs.readFileSync(candFile, 'utf8')).filter(
  (c) => c.camanavaKm >= MIN_CAMANAVA_KM && c.lengthKm <= MAX_ROUTE_KM && !REJECTED_BEFORE.has(c.id),
);
const existing = JSON.parse(fs.readFileSync(existingFile, 'utf8')).filter((r) => r.path.length >= 2);

// Imported routes are saved under this account (the project owner's), as
// they were in October. Change it if someone else runs the import.
const CONTRIBUTOR = 'CTuMyrk8JHhMSKt31xR7AzKKaPP2';

const R = 6371000;
const rad = (d) => (d * Math.PI) / 180;
function meters(a, b) {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}
const lineMeters = (pts) => pts.slice(1).reduce((s, p, i) => s + meters(pts[i], p), 0);

// Flat x/y in metres around a point, fine at city scale.
const toXY = (p, o) => ({ x: rad(p.lon - o.lon) * R * Math.cos(rad(o.lat)), y: rad(p.lat - o.lat) * R });
// Distance from p to segment a–b, and how far along the segment (0–1) the
// closest point is.
function segProject(p, a, b) {
  const A = toXY(a, p), B = toXY(b, p);
  const dx = B.x - A.x, dy = B.y - A.y;
  const len = dx * dx + dy * dy;
  const t = len === 0 ? 0 : Math.max(0, Math.min(1, -(A.x * dx + A.y * dy) / len));
  return { d: Math.hypot(A.x + t * dx, A.y + t * dy), t };
}
const segDist = (p, a, b) => segProject(p, a, b).d;
// Distance from p to a line, and how far along that line (in metres) the
// closest point is. Exact along the segment: segments can be hundreds of
// metres long, and comparing only which segment is closest made two
// directions of the same road look alike.
function nearest(p, line) {
  let best = Infinity, along = 0, bestAlong = 0;
  for (let i = 0; i + 1 < line.length; i++) {
    const seg = meters(line[i], line[i + 1]);
    const { d, t } = segProject(p, line[i], line[i + 1]);
    if (d < best) { best = d; bestAlong = along + t * seg; }
    along += seg;
  }
  return { d: best, along: bestAlong };
}

// Douglas–Peucker, so a route stores a few hundred points, not thousands.
function simplify(pts, tol) {
  if (pts.length < 3) return pts;
  const keep = new Array(pts.length).fill(false);
  keep[0] = keep[pts.length - 1] = true;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let maxD = 0, idx = -1;
    for (let i = s + 1; i < e; i++) {
      const d = segDist(pts[i], pts[s], pts[e]);
      if (d > maxD) { maxD = d; idx = i; }
    }
    if (maxD > tol) { keep[idx] = true; stack.push([s, idx], [idx, e]); }
  }
  return pts.filter((_, i) => keep[i]);
}

// Share of [line] (sampled every ~50 m) running within 30 m of [other] in
// the same direction.
function overlap(line, other) {
  const samples = [];
  let next = 0; // distance into the current segment of the next sample
  for (let i = 0; i + 1 < line.length; i++) {
    const seg = meters(line[i], line[i + 1]);
    for (; next < seg; next += 50) {
      const t = seg === 0 ? 0 : next / seg;
      samples.push({ lat: line[i].lat + (line[i + 1].lat - line[i].lat) * t, lon: line[i].lon + (line[i + 1].lon - line[i].lon) * t });
    }
    next -= seg;
  }
  if (!samples.length) return 0;
  let close = 0, forward = 0, backward = 0, lastAlong = null;
  for (const p of samples) {
    const n = nearest(p, other);
    if (n.d > 30) continue;
    close++;
    if (lastAlong != null) {
      if (n.along > lastAlong + 5) forward++;
      else if (n.along < lastAlong - 5) backward++;
    }
    lastAlong = n.along;
  }
  // Moving backwards along the other line = the opposite direction.
  if (backward > forward) return 0;
  return close / samples.length;
}

const FARES = { Jeepney: [14, 4, 1.94], Bus: [18, 5, 2.22], 'FX/Van': [40, 5, 4.57] };
const SPEED = { Jeepney: 20, Bus: 25, 'FX/Van': 30 };
const PREFIX = { Jeepney: 'osm-jeep', Bus: 'osm-bus', 'FX/Van': 'osm-uv' };
const NOUN = { Jeepney: 'jeepney', Bus: 'bus', 'FX/Van': 'UV Express' };

function schedule(tags) {
  const oh = (tags || '').trim();
  if (/^24\/7$/.test(oh)) return { is24_7: true, startTime: null, endTime: null, text: '24/7' };
  const m = oh.match(/(\d{2}):(\d{2})\s*-\s*(\d{2}):(\d{2})/);
  if (!m) return { is24_7: false, startTime: null, endTime: null, text: null };
  const fmt = (h, mm) => { const H = +h % 24; return `${H % 12 || 12}:${mm} ${H < 12 ? 'AM' : 'PM'}`; };
  return { is24_7: false, startTime: `${m[1]}:${m[2]}`, endTime: `${m[3]}:${m[4]}`, text: `${fmt(m[1], m[2])} - ${fmt(m[3], m[4])}` };
}

const kept = [], dropped = [];
// Newest edit first, so a duplicate keeps the most recently checked one.
candidates.sort((a, b) => (b.timestamp || '').localeCompare(a.timestamp || ''));
for (const c of candidates) {
  const line = simplify(c.line, 6);
  const dupExisting = existing.find((e) => overlap(line, e.path) >= 0.7);
  if (dupExisting) { dropped.push({ c, why: `same road and direction as existing route ${dupExisting.docId} (${dupExisting.start} → ${dupExisting.end})` }); continue; }
  const dupCand = kept.find((k) => overlap(line, k.line) >= 0.95 && overlap(k.line, line) >= 0.95);
  if (dupCand) { dropped.push({ c, why: `same line as candidate ${dupCand.c.id} ${dupCand.c.name}` }); continue; }
  kept.push({ c, line });
}

const docs = kept.map(({ c, line }) => {
  const meta = c;
  const mode = c.mode;
  const from = c.from || c.stopList[0]?.name || 'Start';
  const to = c.to || c.stopList[c.stopList.length - 1]?.name || 'End';
  const km = lineMeters(line) / 1000;
  const [base, baseKm, perKm] = FARES[mode];
  const fare = Math.round(km <= baseKm ? base : base + (km - baseKm) * perKm);
  const sched = schedule(tagsById.get(meta.id)?.opening_hours);
  const designated = c.stopList.length >= 2;
  const sign = `${c.ref ? c.ref + ' ' : ''}${from} – ${to}`;
  const details = [
    c.ref ? `Route ${c.ref}.` : null,
    c.via ? `Via ${c.via}.` : null,
    c.operator ? `Operator: ${c.operator}.` : null,
    designated ? `Stops at ${c.stopList.length} listed stops.` : 'No stops listed; flag it down along the route.',
    'Line and stops from © OpenStreetMap contributors (ODbL).',
  ].filter(Boolean).join(' ');
  return {
    id: `${PREFIX[mode]}-${c.id}`,
    fields: {
      id: `${PREFIX[mode]}-${c.id}`,
      startLocation: from,
      endLocation: to,
      shortDescription: `${mode === 'FX/Van' ? 'UV Express' : mode} ${from} → ${to}${c.via ? ` via ${c.via}` : ''}`,
      steps: [{
        mode,
        instruction: `Ride the ${NOUN[mode]} signed “${sign}” from ${from} to ${to}.`,
        details,
        is24_7: sched.is24_7,
        startTime: sched.startTime,
        endTime: sched.endTime,
        actualFare: null,
        alternateRouteSuggestion: null,
        boarding: designated ? 'designated' : 'flexible',
        ...(designated ? { stops: c.stopList.map((s) => ({ lat: s.lat, lng: s.lon, name: s.name, pickup: s.pickup, dropoff: s.dropoff })) } : {}),
      }],
      startLat: line[0].lat, startLng: line[0].lon,
      endLat: line[line.length - 1].lat, endLng: line[line.length - 1].lon,
      pathPoints: line.map((p) => ({ lat: p.lat, lng: p.lon })),
      stepBoundaries: [line.length - 1],
      eta: String(Math.max(1, Math.round((km / SPEED[mode]) * 60))),
      price: `PHP ${fare}`,
      distance: `${km.toFixed(1)} km`,
      distanceMeters: Math.round(km * 1000),
      schedule: sched.text,
      imageUrl: null,
      audienceTags: [],
      reports: [],
      contributorId: CONTRIBUTOR,
      approvalStatus: 'pending',
      isEdited: false,
      editedAt: null,
      editCount: 0,
      views: 0, upvotes: 0, downvotes: 0,
      staleNeedsReview: false,
      feedbackSummary: { fareAccurateYes: 0, fareAccurateNo: 0, scheduleAccurateYes: 0, scheduleAccurateNo: 0, stillOperatingYes: 0, stillOperatingNo: 0 },
      source: { kind: 'openstreetmap', relationId: c.id, osmVersion: c.version, osmUpdated: c.timestamp },
    },
    preview: { mode, ref: c.ref, name: c.name, km: +km.toFixed(1), camanavaKm: c.camanavaKm, points: line.length, stops: designated ? c.stopList.length : 0, fare, updated: (c.timestamp || '').slice(0, 10) },
  };
});

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'docs.json'), JSON.stringify(docs));
const byMode = docs.reduce((m, d) => ((m[d.preview.mode] = (m[d.preview.mode] || 0) + 1), m), {});
const md = [
  `# OSM import preview`,
  `to save: ${docs.length} ${JSON.stringify(byMode)}; dropped as duplicates: ${dropped.length}`,
  `with listed stops: ${docs.filter((d) => d.preview.stops >= 2).length}; median points per line: ${docs.map((d) => d.preview.points).sort((a, b) => a - b)[docs.length >> 1]}`,
  '',
  '## Dropped as duplicates',
  ...dropped.map(({ c, why }) => `- ${c.id} [${c.ref || '-'}] ${c.name}: ${why}`),
  '',
  '## To save (pending)',
  '| ID | Mode | Ref | Name | km | in CAMANAVA km | Stops | Fare | OSM edited |',
  '| --- | --- | --- | --- | --- | --- | --- | --- | --- |',
  ...docs.sort((a, b) => a.preview.mode.localeCompare(b.preview.mode) || (a.preview.ref || '').localeCompare(b.preview.ref || '', undefined, { numeric: true }))
    .map((d) => `| ${d.id} | ${d.preview.mode} | ${d.preview.ref || ''} | ${d.preview.name} | ${d.preview.km} | ${d.preview.camanavaKm} | ${d.preview.stops || '-'} | ₱${d.preview.fare} | ${d.preview.updated} |`),
];
fs.writeFileSync(path.join(outDir, 'preview.md'), md.join('\n') + '\n');
console.log(md.slice(0, 4).join('\n'));
