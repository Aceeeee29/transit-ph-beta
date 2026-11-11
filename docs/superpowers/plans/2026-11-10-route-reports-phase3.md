# Route Reports and Verification (Phase 3) Implementation Plan

**Goal:** Riders keep live routes accurate without a moderator watching. They report specific problems, enough matching reports act on their own (a "Possibly outdated" label, or a fare fix), rider confirmations verify routes, and search prefers routes riders trust.

**Spec:** `docs/superpowers/specs/2026-11-09-route-moderation-automation-design.md` sections 7, 9 and 13.

**Release:** nothing is released. Phases 1, 2 and 3 ship as one update (Claude's default; the user said "just proceed" without choosing).

## Decisions made while planning

1. **Two kinds of report, kept apart.** The existing "Report an Issue" sheet is about the road right now (traffic, floods, accidents). It stays in Firestore `route_reports`, lasts a day and shows on every route on that road. The new reports are about the route's details (fare, path, stops, schedule, still running). They live in Supabase `route_issues` and count toward the automatic results. The report button asks which kind first.
2. **One table for every source.** A report's `route_key` is the `transit_routes` id for rider and OpenStreetMap routes, or `gtfs:<route_id>` for the DOTC 2013 feed, the same form `correctionOf` uses. GTFS routes have no row, so the "Possibly outdated" label lives in its own table, `route_outdated`, keyed the same way.
3. **What counts.** A report is active while it's open and under 30 days old. A rider has one active report per route and type; a second gets "you already reported this". At most 20 reports per rider per day, against spam. Banned and restricted riders can't report.
4. **"Possibly outdated"** is set when 5 different riders have an active report of the same type on the same route. It doesn't hide the route or send it back to pending (riders would lose it). It goes on a separate "Route problems" list for moderators. A moderator clears it by resolving or dismissing the reports. It also clears by itself when the problem is fixed: an approved path correction settles `wrong_path` reports, and an automatic fare fix settles `wrong_fare` reports.
5. **Automatic fare fix** only for jeepney and bus steps on rider and OpenStreetMap routes (the same modes the fare-only correction handles). It needs 3 different riders whose fares are within ₱1 of each other, on the same step. The new fare is the middle one of those, rounded. It must pass `S_FARE_RANGE`; if not, the reports just count toward "Possibly outdated". A report says which step when the route has more than one ride.
6. **Wrong path** offers "Draw the right way" (opens the existing correction editor) or "Just report it". Drawing sends a correction like today, and the report remembers its id.
7. **Verified by riders** when the route is live and unverified, its trust score (same formula as `route_trust_service.dart`, ported to the server) is at least 60, at least 3 different riders currently say it still runs, it has no active reports, and it isn't "Possibly outdated". Checked after every confirmation and after reports are settled. If a moderator unverified the route, riders can't verify it again; only a moderator can.
8. **Back to unverified** when "Possibly outdated" is set.
9. **Search weights** replace today's ×0.8 preference for rider routes: GTFS, OpenStreetMap and verified rider routes ×1.0, unverified rider routes ×1.15, "Possibly outdated" (any source) ×1.5. Riding a rider route backwards stays about 1.6 times its forward weight, as today (1.3 vs 0.8). The leg shows a "Possibly outdated" warning.
10. **No notifications** from the server (it never writes Firestore). Contributors see the label on their route in Profile.

## Tasks

**Task 1: Database.** `supabase/migrations/20261110000001_route_reports.sql`: `route_issues` (service role only), `route_outdated` (public read), indexes, grants. Adds only.

**Task 2: Rules.** `supabase/functions/routes-api/reports.ts`: pure functions with Deno tests: active reports per type, the fare agreement, the trust score port, the verify decision.

**Task 3: Actions.** `report_issue`, `issue_queue` (staff), `settle_issues` (staff: fixed or dismissed). `quality_feedback` checks verification afterwards. A merged correction settles `wrong_path`, a fare-only correction settles `wrong_fare`. Store methods for both stores.

**Task 4: App.** Report chooser and the new route problem sheet (route screen and planned trips), "Possibly outdated" label next to "Unverified", leg warning, new search weights, Route problems list in the moderator screen.

**Task 5: Dashboard.** Route problems list with resolve and dismiss.

**Task 6: Staging test** (needs the go-ahead, like Phase 2): apply the migration, deploy, then five reports from five accounts, or seeded rows with throwaway uids.

## Status (2026-11-10)

Tasks 1 to 5 written, uncommitted, all automated tests pass (server 208, app 288, dashboard 21 on 2026-11-11).

Task 6 on staging (2026-11-10): migration applied and `routes-api` deployed. Every action passed on real staging tables with seeded rows (fare fix, outdated label, unverify, public reads labels only, GTFS report, queue, settle, auto-verify); the seeded rows were removed. Phone round 1 added two real reports (a wrong fare and a wrong path with a correction), both still open on staging.

Dashboard browser test passed 2026-11-11: Route problems lists both reports, Dismiss closes the wrong fare report, and approving the path correction merged it into its route and settled the `wrong_path` report by itself ("Path corrected"). Live Supabase doesn't have this migration yet.

Known limit: a planned trip's ride on a rider route whose step lines can't all be split (broken `stepBoundaries`) may send a fare report with the wrong step number. The server still checks it's a real ride of that route.

## Review focus

- One rider must not be able to mark a route outdated or change a fare alone.
- A report must never change a route a moderator is reviewing (pending) or a rejected one.
- A failed lookup must never verify a route. It should just leave it as it is.
- Old routes with missing fields or steps must not crash the fare agreement.
