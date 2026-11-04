// Step 1: downloads every bus, jeepney and UV Express route relation that
// passes through the CAMANAVA area from OpenStreetMap (Overpass).
// Usage: node fetch_routes.js <out dir>
// Writes <out dir>/routes_meta.json. Read-only: changes nothing anywhere.
const fs = require('fs');
const path = require('path');

const [, , outDir] = process.argv;
// A box around Caloocan, Malabon, Navotas and Valenzuela. It also catches
// parts of Quezon City and Bulacan; build_candidates.js keeps only routes
// that really run inside the four cities.
const BOX = '14.63,120.90,14.79,121.09';
const QUERY = `[out:json][timeout:180];rel["type"="route"]["route"~"^(bus|share_taxi|minibus)$"](${BOX});out meta;`;
const HOSTS = ['https://overpass-api.de', 'https://overpass.private.coffee'];

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  // The public servers are often "at capacity": keep trying for a while.
  for (let attempt = 0; attempt < 8; attempt++) {
    const host = HOSTS[attempt % HOSTS.length];
    try {
      const res = await fetch(`${host}/api/interpreter`, {
        method: 'POST',
        headers: { 'User-Agent': 'TransitPH/1.0 (route import)', 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'data=' + encodeURIComponent(QUERY),
        signal: AbortSignal.timeout(280000),
      });
      const text = await res.text();
      if (res.ok && text.trimStart().startsWith('{')) {
        const data = JSON.parse(text);
        fs.writeFileSync(path.join(outDir, 'routes_meta.json'), text);
        console.log(`saved ${data.elements.length} route relations from ${host}`);
        return;
      }
      console.error(`${host}: ${res.status} ${text.slice(0, 100).replace(/\s+/g, ' ')}`);
    } catch (e) {
      console.error(`${host}: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 20000));
  }
  console.error('all Overpass attempts failed; try again later (early morning is quieter)');
  process.exit(1);
})();
