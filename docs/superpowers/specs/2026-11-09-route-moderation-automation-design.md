# Route moderation automation — design

Date: 2026-11-09 · Status: approved · Approach: A (all route data moves to Supabase)

## 1. Why

The client's complaints about the current moderator flow:

- Moderators accept or reject routes with no visible conditions. Nobody can say *why* a route was accepted, and the moderator has the full and only say.
- LTFRB routes should come first, with rider routes filling informal gaps or fixing broken official ones.
- Riders can only change a route's trust rating. They can't say what is wrong with it.
- A rejected contributor gets "rejected by moderators" with no reason, and the route is deleted.

What the code does today (checked 2026-11-09):

- Rider and OpenStreetMap routes are Firestore `routes` docs. Every read and write goes through `RouteService` (plus `ModerationService` for the moderator queue).
- Approving or rejecting runs on the moderator's phone. Firestore rules let staff write anything, so a checklist added in the app could be skipped.
- `rejectRoute` deletes the doc and sends a reasonless notification.
- Supabase holds only the old LTFRB GTFS feed (schema `gtfs`: ~1,700 routes, ~91% of trips without a shape), read with the public anon key.
- Fares come from `lib/services/fare_matrix.dart`, our own estimates derived from older LTFRB rates.
- The Firebase project is on the free Spark plan, so no Cloud Functions run.

## 2. Goals and non-goals

Goals:

1. Every submission is checked automatically by fixed, visible rules that run on a server and can't be skipped.
2. Every decision (automatic or moderator) is stored with its reasons and shown to the contributor.
3. Reference routes (DOTC GTFS feed + approved OpenStreetMap routes) are the base layer; rider routes support it.
4. Riders can file specific, structured reports, and enough matching reports change a route's state on their own.
5. Supabase is the main database for all route data.

Non-goals:

- Gemini or any AI deciding to accept or reject. AI output is advice only (phase 4).
- Moving posts, users, notifications, appeals or lockouts out of Firestore.
- Replacing Firebase Auth.
- Changing the short-lived road `route_reports` (1-day disruption notices). They stay as they are; the new reports in phase 3 are about permanent data errors.

## 3. Reference data (what "official" means)

No newer LTFRB data is coming from the client. The reference layer is:

| Source | What it has | Weakness |
|---|---|---|
| DOTC GTFS feed (Supabase `gtfs`) | ~1,700 routes (1,712 under agency "LTFRB"), stop sequences | From 2013; most trips have no path shape; some routes no longer run |
| Approved `osm-*` routes | ~36 routes with real paths | OpenStreetMap volunteer data, not LTFRB |

Where the feed comes from (checked 2026-11-09): our 5 files match Sakay.ph's `gtfs-master` (March 2015), which is the DOTC feed from the 2013 Philippine Transit App Challenge with Sakay's edits. Its calendar runs 2013-06-17 → 2020-06-30. So it predates the 2020 route changes (EDSA Busway, rationalized bus routes). Neither copy has fare files (`fare_attributes`, `fare_rules`), so fares can never come from the feed.

The DOTC license forbids implying affiliation with or endorsement by DOTC. Crediting is optional; the allowed wording is "Data provided by DOTC".

The app labels this layer **"Reference routes"**. Each route shows its real source: "DOTC 2013 data" or "OpenStreetMap", never "official" or "LTFRB-approved". The app also adds a "Data provided by DOTC" credit next to the OpenStreetMap credit.

Missing feed files: our import has `routes`, `trips`, `stop_times`, `stops`, `shapes`. The same zip also has `calendar` (trips already point to its `service_id`s, which don't exist in Supabase today), `frequencies` (1,864 headway rows, i.e. first/last trip and how often) and `agency`. Phase 1 imports these 3 into `gtfs`; they're small. Phase 3 uses `frequencies` for operating hours on reference routes and to compare against `wrong_schedule` reports. `feed_info` is skipped because it has no date or version.

Tricycles are franchised by each city, not LTFRB, so no LTFRB check ever applies to them.

Fares: the team copies the current official LTFRB jeepney and bus fares (base fare, base km, per-km rate) from LTFRB's public announcements into a `fare_rules` table with an effective date and a source note. Until someone enters them, the table starts from today's `fare_matrix.dart` values marked `source = 'TransitPH estimate'`, and fare checks say "estimate" instead of "LTFRB".

## 4. Architecture

```
Flutter app ──read (anon key, RLS: published only)──────────► Supabase Postgres + PostGIS
     │                                                           ▲
     └─write: POST /functions/v1/routes-api                      │ service role
              Authorization: Firebase ID token ──► Edge Function ┘
                                                   │  verifies token (Google keys)
                                                   │  reads users/{uid} from Firestore
                                                   │  (role, ban, restriction) with
                                                   │  the caller's own token
                                                   └─ never writes to Firestore
Dashboard (React) ── same Edge Function, superadmin's Firebase token

After a successful decision, the moderator's app or dashboard writes the
notification and contribution stats to Firestore, same as today.
```

### 4.1 Auth: Edge Function gateway, not Supabase third-party auth

Supabase's built-in Firebase support needs a `role: authenticated` claim on every Firebase user, set by a Cloud Function. Spark can't run those. So:

- **Reads** of published routes use the anon key. RLS allows `SELECT` only on published rows (plus the existing `gtfs` reads).
- **Every write** goes through one Edge Function, `routes-api`, deployed with JWT checking off (`--no-verify-jwt`). It verifies the Firebase ID token itself with `jose.jwtVerify` against Google's public keys (`securetoken@system.gserviceaccount.com`), with `iss = https://securetoken.google.com/<firebase-project-id>` and `aud = <firebase-project-id>`.
- The function reads the caller's `users/{uid}` doc through the Firestore REST API with the caller's own ID token. Rules already let a signed-in user read it, and riders can't change their own `role`. That gives role, ban and restriction with no service account.
- The function writes to Postgres with the service role key, stored as a Supabase secret and never in the app.
- No table grants `INSERT/UPDATE/DELETE` to `anon` or `authenticated`. A modified app can't skip the checks.

Verified by a spike before phase 1 starts (section 10): Firestore REST accepts a Firebase ID token as Bearer; the jose verify works on Supabase's Deno runtime.

### 4.2 One function, many actions

`routes-api` takes `{ action, ...payload }`:

| Action | Who | Phase |
|---|---|---|
| `submit` (new route or correction) | rider, not banned/restricted | 1 (checks in 2) |
| `resubmit` (edit a pending or rejected route) | its contributor | 1 |
| `withdraw` | its contributor | later (dropped from phase 1, no screen needs it; account deletion uses `close_account`) |
| `my_routes` (all own routes, any status, with checks and reasons) | rider | 1 |
| `queue` (routes waiting for a moderator, with checks) | staff | 1 |
| `decide` (approve / reject with reasons / verify) | staff | 1 |
| `vote`, `view`, `quality_feedback` | rider | 1 |
| `close_account` (hand routes over as "Former rider", drop pending) | rider | 1 |
| `report_issue` | rider | 3 |
| `admin_*` (fare rules, reason list) | superadmin | 2 |

## 5. Data model (Supabase, schema `public`)

`transit_routes`: one row per rider or OSM route (the reference GTFS stays in `gtfs`)

| Column | Type | Note |
|---|---|---|
| `id` | text PK | keeps the Firestore id (`osm-bus-…`, rider ids) |
| `source` | enum `rider` / `osm` | |
| `contributor_id` | text null | Firebase uid; null = "Former rider" |
| `contributor_name` | text | |
| `status` | enum `pending` / `published` / `rejected` / `withdrawn` | |
| `verification` | enum `unverified` / `verified` | only meaningful when published |
| `correction_of` | text null | target route id, or `gtfs:<route_id>` for a GTFS feed route |
| `data` | jsonb | the existing `Route.toJson()` shape, so the Dart model barely changes |
| `geom` | geography(LineString,4326) | built from `pathPoints`, used by every geometry check |
| `start_pt`, `end_pt` | geography(Point) | |
| `views`, `upvotes`, `downvotes` | int | moved from Firestore |
| `feedback_summary` | jsonb | same 6 counters as today |
| `revision` | int | +1 on every resubmit |
| `created_at`, `updated_at`, `published_at` | timestamptz | |

`route_checks`: one row per check per revision: `route_id`, `revision`, `code`, `result` (`pass`/`fail`/`flag`/`skip`), `detail` jsonb (numbers shown to people, e.g. `{"fare":30,"expected":"18–22"}`), `rule_version`, `run_at`.

`route_decisions`: the audit log and the contributor-facing history: `route_id`, `revision`, `actor` (`system` or a uid), `decision` (`auto_published`, `auto_rejected`, `flagged`, `approved`, `rejected`, `verified`, `unverified`, `withdrawn`), `reason_codes` text[], `note`, `created_at`. Replaces Firestore `auditLogs` for routes from cutover on. Old `auditLogs` aren't migrated; they stay in Firestore, which is read-only after cutover.

`rejection_reasons`: code, label (English + the app's languages via existing localization keys), `needs_note` bool. Seeded with: `incomplete`, `outside_area`, `wrong_path`, `wrong_fare`, `duplicate`, `not_operating`, `unsafe_or_spam`, `other` (note required).

`route_votes(route_id, user_id, value)`, `route_views(route_id, user_id, last_at)`, `route_quality_feedback(route_id, user_id, fare_ok, schedule_ok, still_operating, created_at)`: moved from the Firestore subcollections, with the same one-per-user and cooldown rules enforced in the function.

`fare_rules` (phase 2): `mode`, `base`, `base_km`, `per_km`, `effective_from`, `source` (the LTFRB memorandum circular it was copied from, or `TransitPH estimate`). The app reads the newest row per mode, replacing the hardcoded numbers (with `fare_matrix.dart` as an offline fallback).

`route_issues` (phase 3): `route_id` (rider/OSM id or `gtfs:<id>`), `reporter_id`, `type`, `payload` jsonb (paid fare, drawn path, note), `status`, `created_at`.

RLS: `transit_routes` `SELECT` where `status = 'published'` for `anon`. Every other table: no client access at all.

## 6. The checklist (phase 2)

Checks are pure TypeScript functions, `(submission, context) → {result, detail}`, run in the Edge Function on every `submit`/`resubmit`. PostGIS answers the geometry questions through a few SQL functions (`st_dwithin`, overlap along a buffer). Each check has a stable code, and its result plus numbers are stored and shown word for word to moderators and the contributor.

### Hard fails: auto-reject, with the reason shown right away

| Code | Rule |
|---|---|
| `H_REQUIRED` | start and end names, ≥1 step, every step has a mode, path has ≥2 points |
| `H_COORDS` | every point is inside the Philippines; no point at 0,0 |
| `H_TARGET` | a correction's target exists and is published (or is a real `gtfs` route) |
| `H_ACCOUNT` | contributor not banned or restricted (from `users/{uid}`) |
| `H_PENDING_LIMIT` | at most 3 pending routes per contributor (today's app-only rule, now enforced) |
| `H_REPEAT` | not ≥90% the same path as one of the contributor's own routes rejected or submitted in the last 7 days |
| `H_FARE_IMPOSSIBLE` | every entered fare is > ₱0 and below 5× the fare-table fare for that mode and distance |

### Soft fails: flagged to a moderator, never auto-rejected

| Code | Rule |
|---|---|
| `S_FARE_RANGE` | jeepney/bus fare within ±₱2 or ±10% (larger one) of the fare table. Tricycle/FX/other: `skip`, "no official fare" |
| `S_AREA` | ≥3 km of the route inside the 4 CAMANAVA cities (same rule as the OSM import) |
| `S_OVERLAP` | not ≥70% the same road, same direction, as a published route or reference route. On a hit the check suggests "submit as a correction of X" |
| `S_CORRECTION_SIZE` | a correction changes ≤40% of the target's path (bigger = probably a different route) |
| `S_DRAWN_GAPS` | no straight jump >300 m between consecutive path points (hand-drawn, not road-following) |
| `S_NEW_CONTRIBUTOR` | account ≥7 days old and has ≥1 published route. New accounts always get a human look |

### Outcomes

- Any hard fail → `rejected` by `system`, with reason codes from the failed checks. The contributor sees it on the submit screen right away, edits, and resubmits.
- Else any soft fail → `pending`, in the moderator queue with the full checklist.
- Else (all pass) → `published` + `unverified` by `system`. It shows in search with an "Unverified" label until riders verify it (phase 3) or a moderator does.

Fare-only corrections (the client's example): a correction whose only change is a jeepney/bus step fare, and where the new fare passes `S_FARE_RANGE`, is applied to the target automatically and logged as `auto_published`.

### Moderator decisions

- **Approve** a flagged route → `published`. If any check flagged, a note is required ("why I'm overriding"). The note is stored in `route_decisions`.
- **Reject** → pick ≥1 reason from `rejection_reasons` (+ note when `needs_note`). The route is kept as `rejected` with its path, not deleted.
- **Verify / unverify** a published route.
- Hard fails never reach moderators, so a moderator can't publish an incomplete or invalid route.

### Rejected routes

- The contributor sees the reasons, the failed checks with their numbers, and the moderator's note in Profile → My routes.
- They can edit and resubmit (new revision, checks run again). Resubmitting is the appeal, so there's no separate appeal flow.
- Rejected rows are purged after 30 days; `route_decisions` rows stay.

## 7. Verification and reports (phase 3)

- **Structured reports** on any route (rider, OSM or GTFS feed) via `report_issue`:
  - `wrong_fare` (with the fare the rider paid)
  - `wrong_path` (with a drawn fix, which becomes a correction submission)
  - `not_operating`
  - `wrong_schedule`
  - `wrong_stop`
  - `other` (note)
- **Aggregation** (run inside `report_issue`, no scheduled jobs):
  - ≥5 different riders, same type, same route, within 30 days → the route gets a "Possibly outdated" label and enters the moderator queue.
  - For `wrong_fare`, if ≥3 riders report the same amount (±₱1) and it passes `S_FARE_RANGE`, the fare updates automatically, logged as `system`.
- **Unverified → verified** automatically when the existing trust score (max 100) is ≥60 *and* ≥3 different riders have confirmed "still operating", with no open issue reports. It falls back to unverified when a "Possibly outdated" label is set.
- **Search ranking** (replaces today's community ×0.8 preference):

  | Route | Weight |
  |---|---|
  | Reference routes and verified rider routes | ×1.0 |
  | Unverified rider routes | ×1.15 |
  | "Possibly outdated" routes (any source) | ×1.5, with a warning on the leg |

## 8. Gemini assist (phase 4)

Called by the Edge Function after the fixed checks, with the key stored as a Supabase secret. It writes advice only, to `route_checks` with result `skip` and code `AI_*`:

- `AI_TEXT`: spam, profanity or nonsense in names and descriptions → shown to the moderator as a hint
- `AI_SUMMARY`: two lines summarizing a flagged route for the moderator
- `AI_MESSAGE`: rewrites reason codes into a friendly rejection message (the codes are still shown)

It never changes a route's status. If Gemini fails or times out, nothing waits on it.

## 9. App and dashboard changes

App (`transit-ph-beta`):

- `RouteService`: reads via the Supabase client; writes via `functions.invoke('routes-api')` with the Firebase ID token. The public method names stay, so the 26 files that call it barely change.
- `Route` model: add `status` values (`rejected`, `withdrawn`), `verification`, `source`, and the latest checks and decisions for own routes.
- Contribute: after submit, show the outcome screen (published as Unverified / waiting for review with flagged checks / rejected with reasons).
- Profile → My routes: status chips, reasons, "Edit and resubmit".
- Moderator screen: queue shows the checklist per route; reason picker on reject; required note when approving over a flag.
- Search and route screens: "Unverified" and "Possibly outdated" labels, a source label on reference routes, the phase 3 weights.
- Report sheet (phase 3) with the structured types.

Dashboard (`F:\transitph-dashboard`): RoutesPage reads Supabase, approves/rejects through `routes-api`; reason picker; checklist panel. Phase 2: fare rules editor.

Notifications (stay in Firestore):

- Moderator decisions: after `decide` succeeds, the moderator's app or dashboard writes the `route_approved` / `route_rejected` notification and the contribution stats. The function itself never writes to Firestore. Rules already let moderators notify anyone.
- Automatic decisions: no notification. The contributor sees the outcome on the submit screen, and later in My routes.
- Road reports (`route_reported`): today's rule checks the contributor by reading Firestore `routes/{id}`, which won't exist for new routes. The rule stops reading that doc. It now accepts any `routeId` when `fromUserId` is the sender and `userId` isn't, so road-report notifications keep working.
- Dead rules after cutover: `routes/*` writes, `routeVotes`, `routeViews`, `routeFeedback`, `isFeedbackSummaryStep`.

## 10. Migration and rollout

1. **Spike (throwaway):** deploy a tiny Edge Function to a second free Supabase project (staging) that verifies a Firebase ID token and reads `users/{uid}` via Firestore REST. Proves 4.1 before anything is built on it.
2. Create schema + RLS on staging; run the Deno check tests and RLS tests there.
3. **Migration script** (`tool/route_migration/`, Node, like `tool/osm_import`): reads Firestore `routes` (+ votes, views, feedback subcollections) with the Firebase CLI token and inserts into Supabase with the service role key passed on the command line, never committed.
   - Approved routes → `published` + `verified`, since a human already approved them.
   - Pending routes → run through the checks.
4. **Cutover release:**
   - New app version reads and writes Supabase.
   - Set `force_update` so old versions update, because they would still write to Firestore.
   - Then deploy Firestore rules that block new `routes` creates and edits. Firestore `routes` stays read-only as a backup for 30 days.
5. Dashboard switches the same day.

## 11. Phases (each gets its own implementation plan)

1. **Foundation:** spike, schema, RLS, `routes-api` with auth, migration, app + dashboard on Supabase, rejected routes kept with moderator-picked reasons, resubmit. `submit` already enforces `H_ACCOUNT` and `H_PENDING_LIMIT` (today's rules, now on the server). Behaviour otherwise the same as today (moderators still decide everything). A moderator's approval in this phase sets `verified`, because a human approved it.
2. **Checklist:** `fare_rules`, all checks, auto-reject / flag / auto-publish-as-Unverified, outcome screen, checklist in moderator views, fare-only corrections.
3. **Reports and verification:** `route_issues`, aggregation, Unverified → verified, "Possibly outdated", new search weights.
4. **Gemini assist.**

## 12. Testing

- **Checks:** Deno unit tests per check with fixture routes, including real ones: the Obando fixtures in `test/obando_routes_fixture.dart` and an OSM route.
- **Auth:** tests with a valid token, an expired token, a wrong project id, a banned user and a non-staff user calling `decide`.
- **RLS:** an anon client can read published rows only and write nothing (run against staging).
- **Dart:** model parsing for the new fields; existing 150+ tests keep passing.
- **Phone:**
  - submit a route that auto-publishes, one that gets flagged, and one that is auto-rejected
  - moderator rejects with a reason, contributor sees it and resubmits
  - search still shows rider routes

## 13. Defaults chosen (change any of them during review)

| Decision | Default |
|---|---|
| Fare tolerance | ±₱2 or ±10%, whichever is larger |
| Service area | ≥3 km inside the 4 CAMANAVA cities |
| New contributor | account <7 days old or no published route yet |
| Verified threshold | trust ≥60 and ≥3 "still operating" confirmations |
| Outdated threshold | 5 riders, same report type, 30 days |
| Rejected kept for | 30 days |
| Existing approved routes | migrated as verified |

## 14. Risks

- **Supabase free tier** pauses a project after a week with no requests, and Edge Functions have a monthly call limit. Check the current pricing page before launch; the app's daily use should keep the project awake.
- **Firestore REST with an ID token** (4.1) is the main unproven piece; the spike settles it first.
- **Old app versions** keep writing to Firestore until they update; `force_update` plus the rules change after cutover handles it.
- **Two databases** for one feature area during migration: Firestore stays read-only, never written, so they can't disagree.
