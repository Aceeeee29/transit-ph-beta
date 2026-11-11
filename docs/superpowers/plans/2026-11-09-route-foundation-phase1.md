# Route Foundation (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move rider and OpenStreetMap routes from Firestore to Supabase. All route writes go through one Edge Function that verifies Firebase logins. Rejected routes are kept with moderator-picked reasons, and contributors can resubmit them.

**Architecture:**
- **Reads:** the app reads published routes straight from Postgres with the anon key (RLS: published only).
- **Writes:** every write goes to the Edge Function `routes-api`. It verifies the Firebase ID token, reads the caller's role and ban status from Firestore with that same token, and writes with the service role.
- **Firestore side effects stay with the caller, same as today:** after a successful decision, the moderator's app or dashboard writes the notification and contribution stats to Firestore.

**Tech Stack:**
- Supabase: Postgres + PostGIS, Edge Functions (Deno), pg_cron
- Libraries: `npm:jose@5.9.6`, `npm:@supabase/supabase-js@2.45.4`, `jsr:@std/assert@^1.0.0`
- App: Flutter `supabase_flutter ^2.12.0`, `firebase_auth`
- Dashboard: React (Vite) in `F:\transitph-dashboard`

**Spec:** `docs/superpowers/specs/2026-11-09-route-moderation-automation-design.md` (sections 4, 5, 9, 10, 11 phase 1)

## Global Constraints

- Firebase project id: `transitph-75da4`. Token issuer `https://securetoken.google.com/transitph-75da4`, audience `transitph-75da4`. Google keys: `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`.
- Roles come from Firestore `users/{uid}.role`: `moderator` or `superadmin` = staff.
- A user is blocked if any of these hold:
  - `isBanned == true`
  - `status == 'banned'`
  - `restrictedUntil` is in the future
- `maxPendingRoutesPerUser = 3`. Quality feedback cooldown: 30 days. Rejected routes are purged 30 days after rejection.
- Rejection reason codes, exactly: `incomplete`, `outside_area`, `wrong_path`, `wrong_fare`, `duplicate`, `not_operating`, `unsafe_or_spam`, `other`. Only `other` needs a note.
- Status values in Postgres: `pending`, `published`, `rejected`, `withdrawn`. In Dart, `published` maps to the existing `RouteApprovalStatus.approved`, so callers don't change.
- No Postgres table gives `insert/update/delete` to `anon` or `authenticated`. The service role key exists only as a Supabase secret and in the user's local shell, never in a repo file.
- Code comments: plain language, short sentences, say why (user rule).
- **Commits and deploys:** commit only when the user says so. `git push`, `supabase db push`, `supabase functions deploy` and `firebase deploy` each need a fresh go-ahead from the user.
- Dashboard edits go in `F:\transitph-dashboard`, never `transit-ph-beta/super-admin-dashboard`.
- Tools run through npx, so nothing gets installed globally. Deno: `npx -y deno@2 …` (tests need `--node-modules-dir=none --no-lock`, because the repo's root `package.json` otherwise makes Deno look for packages in `node_modules`). Supabase CLI: `npx -y supabase …`. Docker isn't installed, so nothing uses `supabase start`.

**Deliberate differences from the spec** (the spec gets updated to match in Task 0):

1. Notifications and contribution stats are written by the caller after `decide`, not by the function. The result is the same, and the function never writes to Firestore.
2. Firestore `auditLogs` aren't migrated. They stay in Firestore, which is read-only after cutover.
3. `withdraw` is dropped from phase 1, since no screen needs it. Account deletion uses `close_account`.
4. Phase 1 approval sets `verification = 'verified'`, because a human approved it.
5. The `route_reported` notification rule no longer reads Firestore `routes`. It accepts any `routeId` when `fromUserId == me` and `userId != me`. This keeps road-report notifications working without the route doc.

## Review Focus

1. **Expired login token.** An app left open for over an hour sends an expired token. Expected: `routes-api` answers 401 `unauthenticated`, `RoutesApi` retries once with `getIdToken(true)`, and the action succeeds. Pinned in Task 7.
2. **Double tap on Approve/Reject.** Expected: the second `decide` gets 409 `conflict` and the app doesn't send a second notification or add stats again. Pinned in Tasks 4 and 8.
3. **Legacy Firestore routes** with no `approvalStatus`, no `pathPoints` or no `createdAt`. Expected: they migrate as published, `geom` stays null, nothing crashes, and the app parses them. Pinned in Tasks 6 and 10.
4. **Supabase unreachable** (offline, or a paused project). Expected: search still uses cached routes, and Contribute shows an error while keeping the drawing; nothing is silently lost. Pinned in Task 8.
5. **Old APKs after cutover.** Expected: their route writes are denied by Firestore rules, and `force_update` sends them to the new version. Pinned in Task 11.

---

### Task 0: Pre-flight (user + one spec edit)

**Files:**
- Modify: `docs/superpowers/specs/2026-11-09-route-moderation-automation-design.md` (record the 5 differences above in section 4.2/9/10)

- [ ] **Step 1:** Ask the user to commit or stash the uncommitted dashboard changes in `F:\transitph-dashboard` (7 modified files, comment rewording only, no behaviour change), so phase 1 doesn't mix with them.
- [ ] **Step 2:** Ask the user to create a second free Supabase project named `transitph-staging`. They should put its URL, anon key and service role key in `F:\transit-ph-beta\.env.staging`, with keys `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`.
- [ ] **Step 3:** Add `.env.staging` to `.gitignore` and check that `git check-ignore .env.staging` prints the path.
- [ ] **Step 4:** Ask the user to run `npx -y supabase login` in their own terminal.
- [ ] **Step 5:** Run `npx -y supabase init` in the repo root. It creates `supabase/config.toml`. Then add:

```toml
[functions.routes-api]
verify_jwt = false
```

- [ ] **Step 6:** Edit the spec with the 5 differences.

### Task 1: Auth gateway and `whoami` (also the spike)

**Files:**
- Create: `supabase/functions/routes-api/auth.ts`, `caller.ts`, `http.ts`, `index.ts`
- Test: `supabase/functions/routes-api/auth_test.ts`, `caller_test.ts`
- Create: `supabase/tests/e2e_whoami.mjs` (the user runs it, with their own test account)

**Interfaces:**
- Produces:
  - `verifyFirebaseToken(token: string, opts: { projectId: string; keys: JWTVerifyGetKey }): Promise<{ uid: string }>`, which throws `HttpError(401, 'unauthenticated')`
  - `googleKeys(): JWTVerifyGetKey`, made with `createRemoteJWKSet` on the Google URL and cached at module level
  - `fetchCaller(uid: string, idToken: string, projectId: string, fetchFn = fetch): Promise<Caller>`, where `Caller = { uid; role: 'rider'|'moderator'|'superadmin'; blocked: boolean; name: string }`
  - `isStaff(c: Caller): boolean`
  - `class HttpError extends Error { status: number; code: string; extra?: Record<string, unknown> }`
  - `json(status, body)` and `corsHeaders`
  - `index.ts` dispatches `{ action }` to a handler map. Success is `200 {ok:true, data}`. `HttpError` becomes `{ok:false, error: code, ...extra}` with its status. `OPTIONS` returns 204 with CORS headers.

- [ ] **Step 1: Write failing tests** in `auth_test.ts`. Use `generateKeyPair('RS256')` + `createLocalJWKSet` to sign tokens:
  - `valid token → uid`
  - `expired token → 401 unauthenticated`
  - `wrong aud (other-project) → 401`
  - `wrong iss → 401`
  - `missing sub → 401`

  In `caller_test.ts`, use a fake `fetchFn` returning Firestore REST JSON:
  - `{fields:{role:{stringValue:'moderator'}}}` → `role 'moderator'`, `blocked false`
  - `isBanned true` → `blocked true`
  - `restrictedUntil` timestamp tomorrow → `blocked true`, yesterday → `false`
  - 404 → `role 'rider'`, `blocked false`
  - 403 → throws `HttpError(401)`

- [ ] **Step 2:** Run `npx -y deno@2 test --node-modules-dir=none --no-lock --allow-env supabase/functions/routes-api/`. Expected: FAIL (modules missing).
- [ ] **Step 3:** Implement `auth.ts` with `jwtVerify(token, keys, { issuer, audience, algorithms: ['RS256'] })`, and `caller.ts` with a GET to `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${uid}` using `Authorization: Bearer ${idToken}`. Then `http.ts` and `index.ts`, with one action, `whoami`, returning `{uid, role, blocked}`. `FIREBASE_PROJECT_ID` is read from `Deno.env`.
- [ ] **Step 4:** Run the tests. Expected: all pass.
- [ ] **Step 5: Deploy to staging** (ask first). Commands:

```bash
npx -y supabase secrets set FIREBASE_PROJECT_ID=transitph-75da4 --remote=<staging-ref> --yes
npx -y supabase functions deploy routes-api --no-verify-jwt --remote=<staging-ref> --yes
```

- [ ] **Step 6: Spike gate.** Write `e2e_whoami.mjs`. It signs in through the Firebase Auth REST API (`accounts:signInWithPassword`, web API key from `lib/firebase_options.dart`) using `TEST_EMAIL` and `TEST_PASSWORD` from the user's environment. Then it POSTs `{action:'whoami'}` and prints the result. The user runs it. Expected: their uid and role. For a Google sign-in account, use `e2e_whoami_google.mjs` instead, which does the same from a page on localhost.
  - **If the Firestore read returns 403/401:** stop. Report back with the fallback: a Google service account key as a Supabase secret, reading `users/{uid}` with an OAuth token. Wait for the user's choice.

### Task 2: Schema, RLS and GTFS extras on staging

**Files:**
- Create: `supabase/migrations/20261109000001_route_foundation.sql`
- Create: `supabase/tests/rls_check.mjs`

**Interfaces:**
- Produces the tables and RPCs that Tasks 3–5 and 10 use. The names are below.

- [ ] **Step 1: Write the migration.** Contents, exactly these names:
  - `create extension if not exists postgis with schema extensions;`
  - `create extension if not exists pg_cron;`
  - Enums:
    - `route_status ('pending','published','rejected','withdrawn')`
    - `route_verification ('unverified','verified')`
    - `route_source ('rider','osm')`
  - `public.transit_routes`: columns as in spec §5, plus `rejected_at timestamptz`.
    - `geom extensions.geography(LineString,4326)` (nullable), `start_pt` and `end_pt` (`geography(Point,4326)`, nullable)
    - `revision int not null default 1`
    - `feedback_summary jsonb not null default '{"fareAccurateYes":0,"fareAccurateNo":0,"scheduleAccurateYes":0,"scheduleAccurateNo":0,"stillOperatingYes":0,"stillOperatingNo":0}'`
    - Indexes on `(status)`, `(contributor_id, status)`, and gist `(geom)`.
  - `public.route_decisions(id bigserial pk, route_id text not null, revision int not null, actor text not null, decision text not null, reason_codes text[] not null default '{}', note text, created_at timestamptz default now())`, with an index on `(route_id, created_at desc)`.
  - `public.rejection_reasons(code text pk, label text not null, needs_note bool not null)`, seeded with the 8 codes. Labels:
    - `incomplete`: "Missing information"
    - `outside_area`: "Outside the service area"
    - `wrong_path`: "Path doesn't match the real route"
    - `wrong_fare`: "Fare is wrong"
    - `duplicate`: "Already exists"
    - `not_operating`: "Route no longer runs"
    - `unsafe_or_spam`: "Spam or unsafe content"
    - `other`: "Other"
  - Engagement tables:
    - `public.route_votes(route_id, user_id, vote text check in ('up','down'), created_at, updated_at, pk(route_id,user_id))`
    - `public.route_views(route_id, user_id, created_at, pk)`
    - `public.route_quality_feedback(route_id, user_id, fare_accurate bool, schedule_accurate bool, still_operating bool, created_at, updated_at, pk)`
  - RPCs (`language plpgsql`; `revoke execute … from public, anon, authenticated`):
    - `route_open(p_route text, p_user text) returns jsonb`: inserts a view row if none exists, and if it inserted, increments `views`. Returns `{vote, feedback, nextFeedbackAt, summary}`.
    - `route_vote(p_route text, p_user text, p_up boolean) returns text`: no vote → insert and +1, return `'up'`/`'down'`. Same vote → delete and −1, return null. Opposite vote → `raise exception 'remove_first'`. This mirrors today's `RouteService.setUserVote`.
    - `route_quality_feedback(p_route text, p_user text, p_fare bool, p_schedule bool, p_operating bool) returns void`: if the last feedback is under 30 days old, `raise exception 'feedback_cooldown:%', <next allowed, ISO UTC>`. Otherwise upsert the row and add the 6 counters plus `lastFeedbackAt` to `feedback_summary`.
    - Unknown route → `raise exception 'route_not_found'`.
  - RLS: enable on every new table. One policy: `published_read on transit_routes for select to anon, authenticated using (status = 'published')`.
  - Grants: Supabase may give new `public` tables to `anon` and `authenticated` by default, so take that away on purpose. `revoke all` on every new table, and on the `route_decisions` id sequence, from `anon, authenticated`. Then `grant select on public.transit_routes to anon, authenticated`. No other grants.
  - GTFS extras:
    - The repo has no SQL for the `gtfs` schema, and staging starts empty. So start with `create schema if not exists gtfs;` and `grant usage on schema gtfs to anon, authenticated, service_role;`. The service role also needs `grant all` on the 3 new tables, since `gtfs_extras.js` writes with it.
    - `gtfs.agency(agency_id text pk, agency_name, agency_url, agency_timezone, agency_lang, agency_phone)`
    - `gtfs.calendar(service_id text pk, monday…sunday smallint, start_date text, end_date text)`
    - `gtfs.frequencies(trip_id text, start_time text, end_time text, headway_secs int, exact_times smallint, pk(trip_id, start_time))`. The key lets `gtfs_extras.js` rerun without doubling rows (all 1,864 rows are unique on it).
    - Select grants and an RLS read policy for `anon`, the same as the existing `gtfs` tables (copy their policy pattern after checking it with `\d+` in the SQL editor).
  - `select cron.schedule('purge-rejected-routes', '0 3 * * *', $$delete from public.transit_routes where status = 'rejected' and rejected_at < now() - interval '30 days'$$);`

- [ ] **Step 2: Write `rls_check.mjs`.** It loads `.env.staging` and uses plain `fetch` to PostgREST. With the anon key, it asserts:
  - select on `transit_routes` returns only `status=published` rows (it seeds 1 published + 1 pending with the service key first)
  - insert on `transit_routes` is rejected with 401/403
  - select on `route_votes` is rejected or returns `[]`
  - `rpc/route_vote` is rejected
  - update and delete on the seeded published row change nothing (a rejected call or 0 rows)

  It exits 1 on any failure and cleans up its seed rows.
- [ ] **Step 3: Apply to staging** (ask first): `npx -y supabase db push --remote=<staging-ref> --yes`. Then ask the user to add `gtfs` to the exposed schemas (Project Settings → Data API), because Task 10 loads the GTFS extras through PostgREST. The schema has to exist before they can pick it.
- [ ] **Step 4:** Run `node supabase/tests/rls_check.mjs`. Expected: `RLS OK (5/5)`.

### Task 3: Route store and row mapping in the function

**Files:**
- Create: `supabase/functions/routes-api/rows.ts`, `store.ts`, `store_supabase.ts`, `store_memory.ts`
- Test: `supabase/functions/routes-api/rows_test.ts`

**Interfaces:**
- Produces:
  - `type RouteRow` (snake_case columns of `transit_routes` + `latest_decision?: Decision`)
  - `type Decision = { decision: string; reason_codes: string[]; note: string|null; actor: string; created_at: string }`
  - `rowFromRouteJson(json: Record<string, unknown>, contributorId: string|null): Omit<RouteRow,'created_at'|'updated_at'|…>`. It strips `views/upvotes/downvotes/approvalStatus/createdAt/updatedAt/feedbackSummary/contributorId` from `data`. It sets `source = id.startsWith('osm-') ? 'osm' : 'rider'`, `correction_of = json.correctionOf ?? null`, and builds `geom` as EWKT `SRID=4326;LINESTRING(lng lat, …)` from `pathPoints` (null if fewer than 2 points), plus `start_pt`/`end_pt` from `startLat/startLng/endLat/endLng`.
  - `interface RouteStore`, with these methods:
    - `get(id)`
    - `countPending(uid, exceptId)`
    - `insert(row)`
    - `update(id, patch, onlyIfStatus?)`, which returns null when the row isn't at that status. `decide` uses it so two moderators deciding at once can't both win.
    - `remove(id)`
    - `listByContributor(uid)`
    - `listByStatus(status)`
    - `listAll()`
    - `addDecision(d: Decision & {route_id; revision})`
    - `latestDecisions(ids: string[]): Map<string, Decision>`
    - `rpc(name, args)`
  - `MemoryStore implements RouteStore` (for tests; `rpc` throws `'not supported'`) and `SupabaseStore implements RouteStore` (service-role client)

- [ ] **Step 1: Failing tests** in `rows_test.ts`:
  - geom EWKT built from 3 points, in lng-lat order
  - 1 point → geom null
  - `osm-bus-1` → source `osm`
  - the counter fields are removed from `data`
  - `correctionOf` is copied to `correction_of`
- [ ] **Step 2:** Run `npx -y deno@2 test --node-modules-dir=none --no-lock --allow-env supabase/functions/routes-api/rows_test.ts`. Expected: FAIL.
- [ ] **Step 3:** Implement `rows.ts`, `store.ts`, `store_memory.ts` and `store_supabase.ts`.
- [ ] **Step 4:** Run the tests. Expected: PASS.

### Task 4: Lifecycle actions

**Files:**
- Create: `supabase/functions/routes-api/actions/lifecycle.ts`
- Modify: `supabase/functions/routes-api/index.ts` (register the actions; `store` is a `SupabaseStore`)
- Test: `supabase/functions/routes-api/lifecycle_test.ts`

**Interfaces:**
- Consumes: `Caller`, `HttpError`, `RouteStore`, `rowFromRouteJson`
- Produces handlers `(caller: Caller, body: any, store: RouteStore) => Promise<unknown>`:

  | Action | Who | What it does |
  |---|---|---|
  | `submit {route}` | not blocked (`403 blocked`) | Needs `id`, `startLocation`, `endLocation` and a non-empty `steps`, else `400 invalid`. More than 3 pending → `409 pending_limit` (resending a route that's already pending doesn't count). Existing id owned by someone else → `409 conflict`. Inserts `status pending`, `revision 1`, and logs decision `submitted`. Returns the row. |
  | `resubmit {route}` | the contributor or staff | Contributor must not be blocked. Sets `pending`, `revision + 1`, replaces `data` and `geom`, clears `rejected_at`, logs `resubmitted`. A staff edit keeps `contributor_id`. |
  | `my_routes {}` | caller | Own rows, any status, with `latest_decision`. |
  | `queue {}` | staff (`403 forbidden` otherwise) | Pending rows, newest first, with `latest_decision`. |
  | `staff_list {}` | staff | All rows with `latest_decision`. |
  | `decide {routeId, decision: 'approve'\|'reject', reasonCodes?, note?}` | staff | See below. |
  | `delete {routeId}` | superadmin only | Deletes the row. |
  | `close_account {}` | caller | Deletes own non-published rows. Published rows get `contributor_id null`, `contributor_name 'Former rider'`, and `data.contributorClosed true`. |

  `submit` also refuses an id starting with `osm-` from anyone who isn't staff (`400 invalid`). The id decides `source`, so otherwise a modified app could pass a rider route off as a reference route.

  `decide` in detail:
  - Not pending → `409 conflict`. The status change uses `update(id, patch, 'pending')`, so it's a conflict even if two moderators get past the first check together.
  - **approve:** if `correction_of` points to a published row, copy these `data` keys into the target: `pathPoints, stepBoundaries, steps, startLat, startLng, endLat, endLng, distance, distanceMeters, eta`. Bump the target's `data.editCount` by 1, rebuild its geom, delete the correction row, and log `approved` on the target with note `correction <id> by <uid> merged`. Return `{mergedInto: target}`. Otherwise set `published`, `verified`, `published_at = now()`, and log `approved`.
  - **reject:** needs ≥1 known code (`400 invalid`), and a note if `other` is picked. Sets `rejected`, `rejected_at = now()`, logs `rejected` with codes and note.
  - Both return `{route, mergedInto?, contributorId, title: '<start> to <end>'}`.

- [ ] **Step 1: Failing tests** with `MemoryStore` and stub callers:
  - `submit as blocked rider → 403 blocked`
  - `4th pending → 409 pending_limit; resending a pending id → ok`
  - `submit missing steps → 400 invalid`
  - `resubmit rejected route → pending, revision 2, rejected_at null`
  - `rider calls decide → 403 forbidden`
  - `reject with [] → 400 invalid`
  - `reject ['other'] without note → 400 invalid`
  - `reject ['wrong_fare'] → status rejected, decision row has codes`
  - `approve twice → second is 409 conflict` (Review Focus 2)
  - `approve correction → target data.steps replaced, editCount 1, correction row gone, mergedInto set`
  - `close_account → pending deleted, published shows Former rider`
  - `delete by moderator → 403`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `lifecycle.ts` and register it in `index.ts`.
- [ ] **Step 4:** Run the tests. Expected: PASS (plus the Task 1 and 3 tests).

### Task 5: Engagement actions

**Files:**
- Create: `supabase/functions/routes-api/actions/engagement.ts`
- Modify: `index.ts`
- Test: `supabase/tests/engagement_check.mjs` (staging, service key, through PostgREST RPC)

**Interfaces:**
- Produces:
  - `open_route {routeId}` → `route_open` RPC result
  - `vote {routeId, up: boolean}` → `{vote: 'up'|'down'|null}`
  - `quality_feedback {routeId, fareAccurate, scheduleAccurate, stillOperating}` → `{}`
  - RPC exceptions map to `HttpError`: `remove_first` → `409 remove_first`; `feedback_cooldown:<iso>` → `429 feedback_cooldown` with `extra {nextAllowedAt}`; `route_not_found` → `404 not_found`
  - All three need a caller who isn't blocked, except `open_route`

- [ ] **Step 1: Write `engagement_check.mjs`.** It seeds a published route and checks:
  - `route_open` twice → views 1
  - vote up → `'up'`, upvotes 1; vote up again → null, upvotes 0
  - vote up then down → error `remove_first`
  - feedback once → counters +1; again → error starting `feedback_cooldown:`

  It cleans up after itself.
- [ ] **Step 2:** Run it against staging. Expected: PASS (the RPCs exist from Task 2).
- [ ] **Step 3:** Implement `engagement.ts` (calls `store.rpc` and maps errors) and register it. Add a Deno test, `engagement_test.ts`, for the error mapping with a stub store whose `rpc` throws each message.
- [ ] **Step 4:** Run `npx -y deno@2 test --node-modules-dir=none --no-lock --allow-env supabase/functions/routes-api/`. Expected: PASS.
- [ ] **Step 5:** Redeploy to staging (ask first). Have the user rerun `e2e_whoami.mjs` with `ACTION=my_routes`. Expected: `[]`.

### Task 6: Dart model and row mapping

**Files:**
- Modify: `lib/models/route.dart`
- Create: `lib/services/route_rows.dart`, `lib/models/route_rejection_reason.dart`
- Test: `test/route_rows_test.dart`

**Interfaces:**
- Produces:
  - `enum RouteApprovalStatus { pending, approved, rejected, withdrawn }`
  - `enum RouteVerification { unverified, verified }`
  - New `Route` fields (all optional with defaults, plus `toJson`/`fromJson` keys of the same name):
    - `verification` (default `verified`)
    - `latestDecision: RouteDecision?`
    - `revision` (default 1)
    - `contributorName: String?`
  - `class RouteDecision { decision; reasonCodes; note; actor; createdAt }` with `fromJson`
  - `Route.fromJson` dates accept a Firestore `Timestamp`, an ISO string, an int in ms, or null, through one private helper `_date(dynamic)`. This includes `editedAt`.
  - `Route.toJson` must produce plain JSON, because it now goes through `jsonEncode`. Today `editedAt` is a Firestore `Timestamp`, which would make `resubmit` throw for any route that's been edited. Send an ISO string instead. Check `route_storage_codec_test.dart` and every other `toJson` caller first.
  - `RouteRows.toRoute(Map<String, dynamic> row) → Route`: starts from `row['data']`, then overrides `id`, `contributorId`, `views/upvotes/downvotes`, `createdAt/updatedAt` (ISO), `verification` and `revision`. Status mapping: `published→approved`, otherwise the same name. `latest_decision` → `latestDecision`, `contributor_name` → `contributorName`.
  - `RouteRows.feedbackSummary(Map row) → Map<String,int>` (6 counters, defaults 0)
  - `class RouteRejectionReason { code; label; needsNote }` with `static const all` (the 8 codes from Global Constraints, same labels as the SQL seed) and `byCode`

- [ ] **Step 1: Failing tests:**
  - published row → `approvalStatus.approved`, verification parsed
  - rejected row with `latest_decision` → reasons and note available
  - legacy data without `createdAt` and with `pathPoints: []` → parses, `createdAt` null (Review Focus 3)
  - ISO, int-ms and `Timestamp` dates all parse
  - `RouteRejectionReason.all.map((r) => r.code)` equals the 8 codes in order
  - Existing tests still pass: `route_storage_codec_test.dart` (the routes saved offline still decode)
- [ ] **Step 2:** Run `flutter test test/route_rows_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test`. Expected: all pass, except the known `widget_test.dart` Firebase-init failure, which predates this work.

### Task 7: `RoutesApi` client

**Files:**
- Create: `lib/services/routes_api.dart`
- Test: `test/routes_api_test.dart`

**Interfaces:**
- Produces:
  - `class RoutesApiException implements Exception { final int status; final String code; final Map<String,dynamic> extra; }`
  - `class RoutesApi`:
    - `static Future<dynamic> call(String action, [Map<String,dynamic> body = const {}])`
    - `@visibleForTesting static Future<({int status, dynamic data})> Function(String action, Map body, String token)? invoker`
    - `@visibleForTesting static Future<String?> Function(bool forceRefresh)? tokenSource`
  - The default invoker uses `Supabase.instance.client.functions.invoke('routes-api', body: {...body, 'action': action}, headers: {'Authorization': 'Bearer $token'})`.
  - The default token source is `FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh)`.
  - No user → `RoutesApiException(401, 'unauthenticated')`.
  - A 401 is retried once with `forceRefresh: true` (Review Focus 1).
  - `{ok:false}` → `RoutesApiException`.
  - Errors map to the existing exceptions so screens don't change:
    - `pending_limit` → `PendingRouteLimitException`
    - `remove_first` → `StateError('remove_first')`
    - `feedback_cooldown` → `StateError('feedback_cooldown:<nextAllowedAt>')`

- [ ] **Step 1: Failing tests** with a fake invoker and token source:
  - `401 then 200 → returns data, token fetched twice (second forced)`
  - `401 twice → RoutesApiException 401`
  - `pending_limit → PendingRouteLimitException`
  - `feedback_cooldown with extra → StateError message 'feedback_cooldown:2026-12-01T00:00:00.000Z'`
  - `no user → 401 without calling invoker`
- [ ] **Step 2:** Run `flutter test test/routes_api_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the test. Expected: PASS.

### Task 8: RouteService and ModerationService on Supabase

**Files:**
- Modify: `lib/services/route_service.dart`, `lib/services/moderation_service.dart`
- Modify: `lib/screens/moderator_screen.dart` (the trust tab and pending list use futures and refresh instead of Firestore streams)
- Test: `test/route_service_supabase_test.dart`

**Interfaces:**
- Consumes: `RoutesApi.call`, `RouteRows`, `Supabase.instance.client`
- Produces (same public names as today). Change these:

  | Method | New behaviour |
  |---|---|
  | `getAllRoutes()` | `from('transit_routes').select(<all columns>).eq('status','published').order('created_at', ascending: false)` → `RouteRows.toRoute`. On error, `[]`, as today, so search falls back to its cache (Review Focus 4). |
  | `watchAllRoutes()` | `Stream.fromFuture(getAllRoutes())` |
  | `getPendingRoutes()` | `RoutesApi.call('queue')` |
  | `getRoutesByUser(uid, {userEmail})` | `my_routes` when `uid` is the signed-in user; otherwise a published select with `.eq('contributor_id', uid)` |
  | `saveRoute(route)` | `submit` |
  | `updateRoute(route)` | `resubmit` |
  | `incrementViewForUser` + `getUserVote` + `getUserRouteQualityFeedback` + `getUserRouteFeedbackNextAllowedAt` | All read one cached `open_route` result per `routeId`, kept for 60 s in a private map, so opening a route costs one call |
  | `setUserVote` | `vote` |
  | `submitRouteQualityFeedback` | `quality_feedback` |
  | `getRouteFeedbackSummary` | a select of `feedback_summary` |
  | `watchRouteFeedbackSummary` | `Stream.fromFuture(getRouteFeedbackSummary(id))` |
  | `approveRoute(id)` | `decide approve`. Then, as today, `_incrementApprovedContributionStats(contributorId)` and the `route_approved` notification. Use the "correction merged" message when `mergedInto` is set. |
  | `rejectRoute(id, {required List<String> reasonCodes, String? note})` | `decide reject`. Then a `route_rejected` notification whose message lists the reason labels, like "Your route (A to B) was rejected: Fare is wrong. Note: …". |
  | `deleteRoute(id)` | `delete` |

  Remove the unused `addReport`, `searchRoutes`, `incrementView`, `incrementUpvote`, `incrementDownvote`, `_markStaleRoutesForReviewIfNeeded`, `_checkPendingLimit` and the Firestore audit-log helpers (grep first: there must be no callers outside the file).
  - `ModerationService`:
    - Drop the Firestore `routes` listener.
    - `refreshPendingRoutes()` fills `pendingRoutesNotifier` from `getPendingRoutes()`. It's called on staff start, after every decision, and on pull-to-refresh.
    - `approveRoute` and `rejectRoute(id, {reasonCodes, note})` delegate to `RouteService`.
    - A `409 conflict` is caught and just triggers a refresh, with no second notification (Review Focus 2).

  Added while building (not in the original table):
  - `getAllRoutes` saves the last good list in a file on the phone and falls back to it. Firestore kept an offline copy by itself and Supabase doesn't, so otherwise a bad connection empties search's rider routes.
  - `getRoutesByUser` and `getPendingRoutes` throw on failure, because an empty answer would make `recalculateUserStats` save zeroed stats and make the queue look finished.
  - `getRouteById`: a published select, then `my_routes` for the caller's own unpublished route. A rejected route's notification opens it.
  - `getAllRoutes` fills a 60-second summary cache, so a list of cards doesn't make one call per card.
  - `watchAllRoutes` is removed. The moderator trust tab holds one `Future` in state, because a fetch inside `build` would call the server on every rebuild.
  - Real decision failures now reach the moderator as a message. They used to be swallowed, which looked like success.

- [ ] **Step 1: Failing tests**, with `RoutesApi.invoker` stubbed:
  - `saveRoute sends action submit with route.toJson()`
  - `rejectRoute sends reasonCodes and note`
  - `approveRoute on 409 conflict does not throw and sends no notification`. Add `@visibleForTesting static Future<void> Function(NotificationModel)? notifyHook` to `RouteService`. When it's set, every route notification goes through it instead of `NotificationsService.addNotification`. The test sets it and asserts it was never called.
  - `getRoutesByUser(self) calls my_routes`
- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement. Keep every public signature except `rejectRoute`.
- [ ] **Step 4:** Run `flutter analyze` and `flutter test`. Expected: no new analyzer issues and all tests pass (apart from the known `widget_test.dart`).

### Task 9: Screens (reject reasons, my routes, account deletion, road-report rule)

**Files:**
- Modify: `lib/screens/moderator_screen_route_cards.dart` (reject button → reason dialog)
- Create: `lib/widgets/moderation/reject_reasons_dialog.dart`
- Modify: `lib/widgets/profile/route_contribution_card.dart` (status chip, reasons, "Edit and resubmit")
- Modify: `lib/services/account_deletion_service.dart` (`_releaseRoutes` → `RoutesApi.call('close_account')`)
- Modify: `firestore.rules` (the `route_reported` branch, difference 5)
- Test: `test/reject_reasons_dialog_test.dart`

**Interfaces:**
- Produces:
  - `Future<({List<String> codes, String? note})?> showRejectReasonsDialog(BuildContext context)`
  - It shows the `RouteRejectionReason.all` chips (multi-select) and a note field.
  - Confirm stays disabled until ≥1 chip is picked and, when `other` is picked, the note isn't blank.
  - Cancel returns null.
  - Style it like the existing restrict-reason dialog in `moderator_screen_route_cards.dart` (around line 618), with the same `_panelCard`/`_metaChip`/`_actionButton` look.

- [ ] **Step 1: Failing widget tests:**
  - `confirm disabled with nothing picked`
  - `other without note keeps confirm disabled`
  - `wrong_fare + confirm returns codes ['wrong_fare'] and null note`
- [ ] **Step 2:** Run `flutter test test/reject_reasons_dialog_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement the dialog and wire it into the reject button (`ModerationService.rejectRoute(route.id, reasonCodes:…, note:…)`).
- [ ] **Step 4:** Update the profile card:
  - The chip shows Pending / Live / Rejected.
  - Rejected shows the reason labels and the moderator's note from `latestDecision`, plus an "Edit and resubmit" button that opens the existing edit flow (`onRouteSubmitted: RouteService.updateRoute`).
- [ ] **Step 5:** Update account deletion, then the rule. The `route_reported` branch becomes:

```
request.resource.data.type == 'route_reported' &&
request.resource.data.get('fromUserId', null) == request.auth.uid &&
request.resource.data.get('routeId', null) is string
```

- [ ] **Step 6:** Add the DOTC credit (spec §3). In `lib/screens/legal_documents_screen.dart` (around line 225, next to the OpenStreetMap sentence), add: "Some routes are based on 2013 transit data from the Department of Transportation and Communications (Data provided by DOTC). TransitPH isn't affiliated with or endorsed by DOTC."
- [ ] **Step 7:** Run `flutter analyze` and `flutter test`. Expected: pass.
- [ ] **Step 8: Phone check on a debug build pointed at staging** (point `.env` at staging temporarily, then restore it; never commit that). Staging has no GTFS data or `find_trip_plan`, so generated routes won't work there. That's expected. This check covers rider routes only:
  - submit a route
  - moderator account: reject with "Fare is wrong" + note
  - contributor sees the reason, edits, resubmits
  - moderator approves
  - the route shows in search

### Task 10: Migration and GTFS extras scripts

**Files:**
- Create: `tool/route_migration/README.md`, `migrate.js`, `gtfs_extras.js`

**Interfaces:**
- `node migrate.js --target <staging|prod> [--dry-run]`:
  - Reads Firestore `routes` and each route's `routeVotes`, `routeViews` and `routeFeedback` subcollections over REST, with the Firebase CLI token, the same way as `tool/osm_import/write.js`.
  - Reads `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` from `.env.staging` or the shell (prod).
  - Upserts through PostgREST with `Prefer: resolution=merge-duplicates`, so it's safe to rerun.
  - Status mapping: approved or missing `approvalStatus` → `published` + `verified`; `pending` → `pending`; `rejected` → `rejected` with `rejected_at = updatedAt`.
  - Owner: use the same field order as `_extractContributorIdentifier` (`contributorId`, `userId`, `contributorEmail`, `userEmail`, `email`). If the value is an email, look up its uid in `users`, because `my_routes` matches by uid only. Print every route whose owner couldn't be resolved. Those keep `contributor_id` null, so nothing is silently given to the wrong person.
  - Timestamps go to ISO. `geom` is built like `rowFromRouteJson` (same rules: null under 2 points).
  - Old `getAllRoutes` used `orderBy('createdAt')`, which silently hides routes with no `createdAt`. Publishing them would make them visible to riders for the first time, so list them in the dry run and ask the user what to do with them.
  - Prints counts per status and per table, plus every route it skipped and why.
- `node gtfs_extras.js --target <…>`: reads `agency.txt`, `calendar.txt` and `frequencies.txt` from `%USERPROFILE%\Downloads\gtfs-master-sakay.ph.zip` (the `unzip -p` output, parsed as CSV), then upserts them into `gtfs.agency`, `gtfs.calendar` and `gtfs.frequencies` with `Content-Profile: gtfs`.

- [ ] **Step 1:** Implement both. In `migrate.js`, export `toRow(doc)` and test it with `node --test tool/route_migration/migrate.test.js`:
  - legacy doc without status/pathPoints/createdAt → published, geom null (Review Focus 3)
  - Firestore `timestampValue` → ISO
  - `osm-` id → source osm
- [ ] **Step 2:** Run `node --test "tool/route_migration/*.test.js"`. Expected: PASS.
- [ ] **Step 3:** Run `node migrate.js --target staging --dry-run`, then for real. Expected: the counts match `routes?showMissing=false` in Firestore. Also run `gtfs_extras.js --target staging`. Expected: 6 agency, 20 calendar, 1,864 frequency rows.
- [ ] **Step 4:** Repeat Task 9 Step 8 with the migrated data: search shows the migrated rider and OSM routes, and old votes and feedback counts are still there.

### Task 11: Dashboard, then cutover

**Files (dashboard repo `F:\transitph-dashboard`):**
- Create: `src/lib/routesApi.ts`, `src/lib/routeRejectionReasons.ts`
- Modify: `src/pages/RoutesPage.tsx`, `src/lib/firestoreApi.ts` (remove `getRoutes`/`updateRouteStatus`/`deleteRoute`; keep `notifyRouteReviewed` and `incrementApprovedContributionStats`, export them)

**Files (app repo):**
- Modify: `firestore.rules` (routes read-only), `pubspec.yaml` (version), `CHANGELOG.md`

**Interfaces:**
- `callRoutesApi(action: string, body?: object): Promise<any>`:
  - POSTs to `${VITE_SUPABASE_URL}/functions/v1/routes-api` with `apikey: VITE_SUPABASE_ANON_KEY` and `Authorization: Bearer ${await auth.currentUser.getIdToken()}`.
  - Retries once on 401 with `getIdToken(true)`.
  - Throws `Error(code)` on `{ok:false}`.
- `ROUTE_REJECTION_REASONS`: the same 8 `{code,label,needsNote}`.

- [ ] **Step 1:** Implement the dashboard changes:
  - RoutesPage lists via `staff_list`.
  - Reject opens a reason picker (same rules as the app dialog).
  - Approve/reject call `decide`, then the existing notify/stats helpers, which are skipped on `conflict`.
  - Rows show status and the latest reasons.
  - Delete calls `delete`.
  - Add `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` to `.env.example`. The user sets them in Vercel.
  Added while building (not in the original list):
  - `subscribeDashboardStats` watched Firestore `routes` live, and `getModeratorStats` read Firestore approvals, so both would freeze at cutover. Stats now refresh routes every 60 seconds. The Moderators page adds a new superadmin action, `moderator_approvals`, to its Firestore history.
  - Only pending rows get Approve and Reject. The old page let you act on rejected rows, which the server now refuses. Rejected rows get Delete instead.
  - Only `VITE_SUPABASE_URL` is needed, because `routes-api` runs without Supabase's JWT check. **Set it in Vercel before merging**, or every route call fails.
  - The dashboard's work is on its own local `route-foundation` branch, not `main`.

- [ ] **Step 2:** Run `npm run build` in the dashboard. Expected: success with no type errors. Then `npm run dev` against staging: reject with a reason and approve one route.
- [ ] **Step 3: Cutover**, in this order. Each step needs a go-ahead.

  Before anything touches production, back it up, because the free project has no restore we've tested:
  - Export the 5 `gtfs` tables. `supabase_datasets/*.csv` isn't enough: its contents differ from live (exact counts on 2026-11-09: trips 1,986 live vs 1,988, stops 4,858 vs 4,849, and 2 live routes aren't in it).
  - Save `find_trip_plan`, the `gtfs` policies and grants. None of it is in git. `npx -y supabase db query --read-only --remote=<ref> -f <file> -o json` reads them without a manual copy.
  - Done 2026-11-09, in `F:\transitph-backups\2026-11-09-before-cutover`, outside the repo. Repeat right before Step 3 item 1 if much time has passed.

  1. `supabase db push` and `functions deploy` to the **production** project.
  2. `node migrate.js --target prod` + `gtfs_extras.js --target prod`.
  3. Bump the version, add a CHANGELOG entry, build the APK.
  4. User publishes it, then sets `latest_version` + `force_update = true`.
  5. Deploy the Firestore rules: `routes` and its subcollections become `allow write: if false` (read stays), plus the Task 9 `route_reported` change (Review Focus 5).
  6. The user deploys the dashboard to Vercel.
- [ ] **Step 4:** Rerun `rls_check.mjs` and `engagement_check.mjs` against prod with read-only seeds (`--target prod`). Then phone-check one submit → reject → resubmit → approve cycle on the release build.
