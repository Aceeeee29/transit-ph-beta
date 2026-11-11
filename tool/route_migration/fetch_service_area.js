// Builds the SQL rows for public.service_areas: the 4 CAMANAVA city borders from
// OpenStreetMap, simplified. Run once. Its output went into the
// 20261109000002_route_checklist.sql migration.
// Usage: node tool/route_migration/fetch_service_area.js <out.sql>
const fs = require('fs');

const QUERY = '[out:json][timeout:180];rel["boundary"="administrative"]["admin_level"="6"]["name"~"^(Caloocan|Malabon|Navotas|Valenzuela)$"];out geom;';
const ENDPOINTS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];

// About 15 m. City borders don't need more, and it keeps the migration small.
const TOLERANCE_DEGREES = 0.00015;

function distanceToSegment(p, a, b) {
  const dx = b.lon - a.lon;
  const dy = b.lat - a.lat;
  if (dx === 0 && dy === 0) return Math.hypot(p.lon - a.lon, p.lat - a.lat);
  const t = Math.max(0, Math.min(1, ((p.lon - a.lon) * dx + (p.lat - a.lat) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(p.lon - (a.lon + t * dx), p.lat - (a.lat + t * dy));
}

// Douglas-Peucker. A way's two ends always stay, so the ways still join up into
// closed shapes afterwards.
function simplify(points) {
  if (points.length < 3) return points;
  let furthest = 0;
  let index = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = distanceToSegment(points[i], points[0], points[points.length - 1]);
    if (d > furthest) {
      furthest = d;
      index = i;
    }
  }
  if (furthest <= TOLERANCE_DEGREES) return [points[0], points[points.length - 1]];
  return [...simplify(points.slice(0, index + 1)).slice(0, -1), ...simplify(points.slice(index))];
}

async function overpass() {
  for (const endpoint of ENDPOINTS) {
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'TransitPH-route-tools' },
        body: `data=${encodeURIComponent(QUERY)}`,
        signal: AbortSignal.timeout(200000),
      });
      if (response.ok) return await response.json();
      console.error(`${endpoint}: ${response.status}`);
    } catch (error) {
      console.error(`${endpoint}: ${error.message}`);
    }
  }
  throw new Error('Overpass failed');
}

(async () => {
  const { elements } = await overpass();
  const rows = [];
  for (const city of elements) {
    const ways = city.members.filter((m) => m.type === 'way' && m.role === 'outer' && m.geometry);
    const lines = ways.map((m) => {
      const points = simplify(m.geometry).map((p) => `${p.lon.toFixed(6)} ${p.lat.toFixed(6)}`);
      return `(${points.join(',')})`;
    });
    const before = ways.reduce((n, m) => n + m.geometry.length, 0);
    const after = lines.reduce((n, l) => n + l.split(',').length, 0);
    console.log(`${city.tags.name}: ${ways.length} ways, ${before} points down to ${after}`);
    rows.push(`  ('${city.tags.name}', 'MULTILINESTRING(${lines.join(',')})')`);
  }
  const names = elements.map((e) => e.tags.name).sort().join(',');
  if (names !== 'Caloocan,Malabon,Navotas,Valenzuela') throw new Error(`Unexpected cities: ${names}`);
  fs.writeFileSync(process.argv[2], rows.join(',\n'));
  console.log(`wrote ${fs.statSync(process.argv[2]).size} bytes`);
})().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
