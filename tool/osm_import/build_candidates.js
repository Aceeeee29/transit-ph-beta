// Step 2: builds TransitPH route candidates from OSM route relations.
// Usage: [FILL_IDS=id,id] node build_candidates.js <routes_meta.json> <out dir>
// Reads relation tags from the first file, downloads geometry, stops and
// the CAMANAVA city borders from Overpass, and writes candidates.json +
// rejected.json + summary.txt to <out dir>. Writes nothing anywhere else.
const fs = require('fs');
const path = require('path');

const [, , metaFile, outDir] = process.argv;
const HOSTS = ['https://overpass-api.de', 'https://overpass.private.coffee', 'https://overpass-api.de'];

async function overpass(query, label) {
  // Each answer is kept on disk, so a rerun doesn't download it again.
  const cache = path.join(outDir, `cache_${label.replace(/\W+/g, '_')}.json`);
  if (fs.existsSync(cache)) return JSON.parse(fs.readFileSync(cache, 'utf8'));
  const data = await overpassFetch(query, label);
  fs.writeFileSync(cache, JSON.stringify(data));
  return data;
}

async function overpassFetch(query, label) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const host = HOSTS[attempt % HOSTS.length];
    try {
      const res = await fetch(`${host}/api/interpreter`, {
        method: 'POST',
        headers: { 'User-Agent': 'TransitPH/1.0 (route import)', 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'data=' + encodeURIComponent(query),
        signal: AbortSignal.timeout(280000),
      });
      const text = await res.text();
      if (res.ok && text.trimStart().startsWith('{')) return JSON.parse(text);
      console.error(`${label}: ${host} ${res.status} ${text.slice(0, 120).replace(/\s+/g, ' ')}`);
    } catch (e) {
      console.error(`${label}: ${host} ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 15000));
  }
  throw new Error(`${label}: all Overpass attempts failed`);
}

const R = 6371000;
const rad = (d) => (d * Math.PI) / 180;
function meters(a, b) {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}
const lineMeters = (pts) => pts.slice(1).reduce((s, p, i) => s + meters(pts[i], p), 0);

// Ray casting over all outer-ring segments; ring order doesn't matter.
function inside(p, segs) {
  let c = false;
  for (const [a, b] of segs) {
    if ((a.lat > p.lat) !== (b.lat > p.lat) &&
        p.lon < ((b.lon - a.lon) * (p.lat - a.lat)) / (b.lat - a.lat) + a.lon) c = !c;
  }
  return c;
}

// Routes whose gaps may be filled by road routing (comma-separated ids).
const FILL = new Set((process.env.FILL_IDS || '').split(',').filter(Boolean).map(Number));

// The car route between the two ends of a gap, or null when the router
// fails or the drive is far longer than the gap (a wrong way around).
async function roadBridge(from, to, gapMeters) {
  const url = `https://router.project-osrm.org/route/v1/driving/${from.lon},${from.lat};${to.lon},${to.lat}?overview=full&geometries=geojson`;
  try {
    const res = await fetch(url, { headers: { 'User-Agent': 'TransitPH/1.0 (route import)' }, signal: AbortSignal.timeout(15000) });
    const data = await res.json();
    if (data.code !== 'Ok' || !data.routes?.length) return null;
    const pts = data.routes[0].geometry.coordinates.map(([lon, lat]) => ({ lat, lon }));
    const drive = lineMeters(pts);
    if (drive > gapMeters * 3 + 300) {
      console.error(`bridge too long: ${Math.round(gapMeters)} m gap, ${Math.round(drive)} m drive`);
      return null;
    }
    return pts;
  } catch (e) {
    console.error(`bridge failed: ${e.message}`);
    return null;
  }
}

const EXCLUDED_NETWORKS =/interregional|inter-regional|region iii|victory liner|^p2p$/i;

function kindOf(t) {
  // UV Express is tagged like jeepneys (share_taxi), so check it first.
  if (/uv/i.test(t.network || '') || /uv express/i.test(t.name || '')) return 'FX/Van';
  if (t.route === 'share_taxi' || t.bus === 'share_taxi' || /puj/i.test(t.network || '')) return 'Jeepney';
  return 'Bus';
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const all = JSON.parse(fs.readFileSync(metaFile, 'utf8')).elements.filter((e) => e.type === 'relation');
  const rejected = [];
  const keep = [];
  for (const r of all) {
    const t = r.tags;
    if (EXCLUDED_NETWORKS.test(t.network || '')) rejected.push({ id: r.id, name: t.name, why: `provincial/premium network (${t.network})` });
    else if (/carousel/i.test(t.name || '')) rejected.push({ id: r.id, name: t.name, why: 'EDSA Carousel is already in the transit data' });
    else if (t['disused:route']) rejected.push({ id: r.id, name: t.name, why: 'marked disused' });
    else keep.push(r);
  }

  // City borders.
  const borders = await overpass(
    '[out:json][timeout:180];rel["boundary"="administrative"]["name"~"^(Caloocan|Malabon|Navotas|Valenzuela)$"];out geom;',
    'borders',
  );
  // The four cities only (admin_level 6). Barangays elsewhere share these
  // names, and overlapping borders checked together cancel each other out.
  const cityBorders = [];
  const cities = [];
  for (const b of borders.elements) {
    if (b.tags.admin_level !== '6') continue;
    cities.push(b.tags.name);
    const segs = [];
    for (const m of b.members) {
      if (m.type !== 'way' || m.role !== 'outer' || !m.geometry) continue;
      for (let i = 0; i + 1 < m.geometry.length; i++) segs.push([m.geometry[i], m.geometry[i + 1]]);
    }
    cityBorders.push(segs);
  }
  const segs = cityBorders.flat();
  const inCamanava = (p) => cityBorders.some((city) => inside(p, city));

  // Geometry, way tags and stop nodes for the kept relations, in batches.
  const ids = keep.map((r) => r.id);
  const geom = new Map(), wayTags = new Map(), nodes = new Map();
  for (let i = 0; i < ids.length; i += 40) {
    const batch = ids.slice(i, i + 40).join(',');
    const data = await overpass(
      `[out:json][timeout:240];rel(id:${batch})->.r;.r out geom;way(r.r);out tags;node(r.r);out;`,
      `geometry ${i}`,
    );
    for (const e of data.elements) {
      if (e.type === 'relation') geom.set(e.id, e);
      else if (e.type === 'way') wayTags.set(e.id, e.tags || {});
      else if (e.type === 'node') nodes.set(e.id, e);
    }
  }

  const candidates = [];
  for (const r of keep) {
    const g = geom.get(r.id);
    const t = r.tags;
    if (!g) { rejected.push({ id: r.id, name: t.name, why: 'geometry download missing' }); continue; }
    const ways = g.members.filter((m) => m.type === 'way' && (m.role === '' || m.role === 'route' || m.role === 'forward' || m.role === 'backward') && m.geometry);
    const notRoad = ways.filter((m) => !wayTags.get(m.ref)?.highway);
    // Join the ways in order, flipping each to meet the line so far.
    let line = [];
    const gaps = [];
    const filled = [];
    for (const m of ways) {
      let pts = m.geometry.map((p) => ({ lat: p.lat, lon: p.lon }));
      if (line.length === 0) {
        // Orient the first way toward the second.
        const next = ways[1]?.geometry;
        if (next) {
          const ends = [next[0], next[next.length - 1]];
          const dStart = Math.min(...ends.map((e) => meters(pts[0], e)));
          const dEnd = Math.min(...ends.map((e) => meters(pts[pts.length - 1], e)));
          if (dStart < dEnd) pts.reverse();
        }
        line = pts;
        continue;
      }
      const tail = line[line.length - 1];
      const toStart = meters(tail, pts[0]), toEnd = meters(tail, pts[pts.length - 1]);
      if (toEnd < toStart) pts.reverse();
      const gap = Math.min(toStart, toEnd);
      if (gap > 30) {
        // Only for routes the user approved filling: drive the missing
        // stretch along the roads instead of jumping across it.
        const bridge = FILL.has(r.id) ? await roadBridge(tail, pts[0], gap) : null;
        if (bridge) {
          line.push(...bridge.slice(1, -1));
          filled.push(Math.round(gap));
        } else {
          gaps.push(Math.round(gap));
        }
      }
      line.push(...(gap < 1 ? pts.slice(1) : pts));
    }
    const total = line.length >= 2 ? lineMeters(line) : 0;
    let camanavaMeters = 0;
    for (let i = 0; i + 1 < line.length; i++) {
      if (inCamanava(line[i]) && inCamanava(line[i + 1])) camanavaMeters += meters(line[i], line[i + 1]);
    }
    // Stops in route order: stop positions and platforms that have a name.
    const stops = [];
    for (const m of g.members) {
      if (m.type !== 'node' || !/^(stop|platform)/.test(m.role)) continue;
      const n = nodes.get(m.ref);
      const name = n?.tags?.name;
      if (!n || !name) continue;
      const last = stops[stops.length - 1];
      if (last && (last.name === name || meters(last, n) < 40)) continue;
      stops.push({
        lat: n.lat, lon: n.lon, name,
        pickup: !/exit_only/.test(m.role), dropoff: !/entry_only/.test(m.role),
      });
    }
    const info = {
      id: r.id, version: r.version, timestamp: r.timestamp,
      name: t.name, ref: t.ref || null, from: t.from || null, to: t.to || null, via: t.via || null,
      network: t.network || null, operator: t.operator || null,
      mode: kindOf(t),
      lengthKm: +(total / 1000).toFixed(2), camanavaKm: +(camanavaMeters / 1000).toFixed(2),
      gaps, filledGaps: filled, notRoadWays: notRoad.length, wayCount: ways.length, stops: stops.length,
    };
    let why = null;
    if (line.length < 2) why = 'no line';
    else if (gaps.length) why = `line has ${gaps.length} gap(s): ${gaps.slice(0, 5).join(', ')} m`;
    else if (notRoad.length) why = `${notRoad.length} piece(s) not tagged as road`;
    else if (total < 1000) why = 'shorter than 1 km';
    else if (camanavaMeters < 1000) why = `only ${info.camanavaKm} km inside CAMANAVA`;
    if (why) { rejected.push({ ...info, why }); continue; }
    candidates.push({ ...info, line, stopList: stops });
  }

  fs.writeFileSync(path.join(outDir, 'candidates.json'), JSON.stringify(candidates));
  fs.writeFileSync(path.join(outDir, 'rejected.json'), JSON.stringify(rejected, null, 1));
  const count = (xs, f) => xs.reduce((m, x) => ((m[f(x)] = (m[f(x)] || 0) + 1), m), {});
  const lines = [
    `borders: ${cities.join(', ')} (${segs.length} border segments)`,
    `relations: ${all.length}; candidates: ${candidates.length}; rejected: ${rejected.length}`,
    `candidates by mode: ${JSON.stringify(count(candidates, (c) => c.mode))}`,
    `candidates with 2+ named stops: ${candidates.filter((c) => c.stops >= 2).length}`,
    `rejected by reason: ${JSON.stringify(count(rejected, (x) => x.why.replace(/[\d.,]+/g, 'N')))}`,
  ];
  fs.writeFileSync(path.join(outDir, 'summary.txt'), lines.join('\n') + '\n');
  console.log(lines.join('\n'));
})().catch((e) => { console.error(e); process.exit(1); });
