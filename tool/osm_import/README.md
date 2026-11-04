# OSM route import

Imports bus, jeepney and UV Express routes from OpenStreetMap into Firestore
`routes` as **pending**, for moderators to review. Approved ones are used by
search like rider routes, without the "Community route" / "Rider-verified"
labels (ids start with `osm-`, see `Route.isFromOpenStreetMap`).

Run with Node 18+ from this folder. Use a work folder outside the repo (it
fills up with downloads), e.g. `C:\temp\osm`.

| Step | Command | Writes to Firestore? |
| --- | --- | --- |
| 1. Download the route list | `node fetch_routes.js C:\temp\osm` | No |
| 2. Build lines and checks | `node build_candidates.js C:\temp\osm\routes_meta.json C:\temp\osm\build` | No |
| 3. Read existing routes | `firebase projects:list` (refreshes the login), then `node read_routes.js C:\temp\osm\existing.json` | No |
| 4. Preview | `node prepare.js C:\temp\osm\build\candidates.json C:\temp\osm\existing.json C:\temp\osm\prep C:\temp\osm\routes_meta.json` | No |
| 5. Save as pending | `node write.js C:\temp\osm\prep\docs.json 3 50` | **Yes** |

Read `C:\temp\osm\prep\preview.md` (and `build\rejected.json`) before step 5.
Step 5 is all-or-nothing and never overwrites an existing route, so running
it twice can't create duplicates.

## What gets kept

- **Networks:** local city buses, jeepneys and UV Express. Interregional,
  Region III, Victory Liner and P2P buses are skipped, and so is the EDSA
  Carousel (already in the transit data).
- **Lines:** every piece must be a mapped road with no gap over 30 m.
  Lines are simplified to within 6 m.
- **Serves CAMANAVA:** at least 3 km inside Caloocan, Malabon, Navotas or
  Valenzuela, and at most 50 km long (`prepare.js`).
- **Not already there:** routes running at least 70% on the same road, in
  the same direction, as an existing route are dropped. Both directions of
  a route are kept as separate routes.
- **Not rejected before:** `REJECTED_BEFORE` in `prepare.js` lists OSM
  routes moderators deleted. Add to it when they reject more.

## Routes with gaps

A route whose OSM line has gaps is rejected in step 2. To fill small gaps
by road routing, pass their ids:
`FILL_IDS=14996196,10393521 node build_candidates.js …`. A fill is refused
when the drive is much longer than the gap (pieces out of order in OSM).
Better: fix the route in OpenStreetMap itself, then rerun.

Known to need an OSM fix (2026-11-04): UV Express Monumento → Novaliches
(14996197), Novaliches–South Supermarket Malinta (8202651), Route 20
(9453756), Route 51 VGC → Cubao (15019282).

## Notes

- Overpass is often "at capacity". Every download is saved in the work
  folder, so a rerun continues where it stopped. Early morning is quieter.
- Credit: OSM data is ODbL. Each route's details say "© OpenStreetMap
  contributors"; the app also needs that line somewhere visible.
- Fares are left empty (riders see the estimated fare). The whole-route
  price is the fare-matrix estimate.
