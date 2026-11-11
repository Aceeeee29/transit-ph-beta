# Route Checklist (Phase 2) Implementation Plan

**Goal:** Every submission is checked by fixed rules on the server. Hard fail: rejected right away with the reason. Soft fail: goes to a moderator with the checklist. All pass: published as Unverified. Moderators stop being needed for every route.

**Spec:** `docs/superpowers/specs/2026-11-09-route-moderation-automation-design.md` sections 5, 6, 9, 11 (phase 2).

**Release:** nothing is released. Phase 1 and Phase 2 ship as one update.

## Decisions made while planning

1. `H_ACCOUNT` and `H_PENDING_LIMIT` stay as refusals (403 and 409), with no row stored. A banned rider's route shouldn't be stored and shown as "rejected", and the pending limit is about the queue, not the route.
2. A request with no usable `id` stays `400 invalid`, because there's nothing to store it under. Every other `H_REQUIRED` failure is stored as rejected, so the rider sees why.
3. `H_REPEAT` ignores routes the system rejected. Otherwise a rider who fixes an auto-rejected route on the same screen would be blocked by their own first attempt. Routes a moderator rejected still count.
4. A staff edit never auto-publishes. Hard fail: rejected. Anything else stays pending, as it does today, because the moderator is reviewing it.
5. Each check stores its message text, so the app, dashboard and contributor all show the same words.
6. `S_OVERLAP` compares lines for rider and OSM routes. For the GTFS feed it compares stop sequences, because almost no trips have a shape.
7. Bus fares accept anything from the ordinary to the aircon fare, since the same road has both. Students' 20% discount fits inside the jeepney range on short trips.
8. Fare-only corrections apply to the target's steps and `price`, and no correction row is kept.
9. The 72-hour auto-publish isn't included. It wasn't requested. Flagged routes wait for a moderator.

## Tasks

**Task 1: Database.** `supabase/migrations/20261109000002_route_checklist.sql`: `route_checks`, `fare_rules`, `service_areas` (CAMANAVA borders from OpenStreetMap), `route_geometry_facts` RPC, all service-role only except `fare_rules` read. Load the GTFS backup into staging for testing.

**Task 2: Checks.** `supabase/functions/routes-api/checks.ts`: pure functions, Deno tests per check.

**Task 3: Actions.** `submit` and `resubmit` run the checks and pick the outcome. Fare-only corrections. `decide` needs a note to approve over a flag, and gains verify and unverify. Lists include checks. Admin fare rule actions.

**Task 4: App.** Outcome screen after submit, checklist on moderator cards, note when approving over a flag, verify button, failed checks in Profile, Unverified label, fares read from `fare_rules` with `fare_matrix.dart` as the offline fallback.

**Task 5: Dashboard.** Checklist in the preview, note when approving over a flag, verify and unverify, fare rules editor.

**Task 6: Phone and browser test on staging.** Submit one route that publishes, one that's flagged and one that's auto-rejected.

## Status (2026-11-11)

Tasks 1 to 5 written, uncommitted. Rule version 2 (the user's choices from 2026-11-10) is in `checks.ts` and `20261110000002_route_rules_v2.sql`. Automated tests pass: server 208, app 288, dashboard 21, migration tools 28.

Staging has all three migrations, the GTFS backup and the current `routes-api`. On the 62 real routes, 16 of 29 rider routes would auto-publish.

Task 6 is half done. Phone round 1 (2026-11-10) was submitted from the moderator account, so it tested the flagged and rejected paths but not auto-publish. `H_REPEAT` was found one-way there and fixed. Still to do:

- Phone with a throwaway rider account, 2026-11-11: flagged (only `S_NEW_CONTRIBUTOR`) and auto-rejected (`H_FARE_IMPOSSIBLE`, ₱100) both worked. Auto-publish can't be tested from a new account (it's flagged for 7 days by design) and the user has no older rider account, so it's covered by server tests and the real-route dry run only.
- Found: after an automatic rejection the editor kept the drawing, but the rejected route was already saved in Profile, and sending again created a second route. Fixed 2026-11-11: `RouteService.saveRoute` re-sends a route the checks just rejected as `resubmit`, and the dialog says it's saved as rejected, with "Fix it now" and "Fix later". Phone retest passed: a ₱100 route fixed to ₱14 stayed one row (revision 2, pending), and "Fix later" left the rejected route in Profile.
- ~~Dashboard in the browser~~ passed 2026-11-11 on staging: checklist in the preview, flag text in the list, note required to approve over a flag, unverify and verify, fare rates table (no rate saved).

Live Supabase got all three migrations (Phase 2, Phase 3, rule v2) and `routes-api` version 2 on 2026-11-11, run by the user. Checked read-only: LTFRB rates in use for jeepney, modern jeepney, bus and aircon bus; the public can only read `fare_rules` and `route_outdated`; the function refuses bad logins. A real submit against live is still unproven.

## Review focus

- A rider must never lose their drawing because of a rejection.
- A route that fails to check (database error) must not be published. It goes to a moderator instead.
- Checks must not crash on old routes with missing fields.
- Editing an auto-rejected route must not be blocked by `H_REPEAT` against itself.
