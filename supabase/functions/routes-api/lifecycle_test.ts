import { assert, assertEquals, assertRejects } from "jsr:@std/assert@^1.0.0";
import { lifecycle } from "./actions/lifecycle.ts";
import type { Caller } from "./caller.ts";
import { HttpError } from "./http.ts";
import type { RouteRow } from "./rows.ts";
import { MemoryStore } from "./store_memory.ts";

const rider = (uid = "rider-1", blocked = false): Caller => ({
  uid,
  role: "rider",
  blocked,
  name: "Rider One",
  createdAt: null,
});
const moderator: Caller = { uid: "mod-1", role: "moderator", blocked: false, name: "Mod", createdAt: null };
const superadmin: Caller = { uid: "admin-1", role: "superadmin", blocked: false, name: "Admin", createdAt: null };

const route = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  startLocation: "Monumento",
  endLocation: "Malabon",
  steps: [{ mode: "Jeepney", instruction: "Ride" }],
  pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.66, lng: 120.99 }],
  ...extra,
});

type Result = RouteRow & { route: RouteRow; mergedInto?: string; contributorId: string | null; title: string };

function setup() {
  const store = new MemoryStore();
  // New riders' routes are always flagged, and approving a flag needs a note.
  // Most tests here are about something else, so they get one by default.
  const run = async (action: string, caller: Caller, body: Record<string, unknown> = {}) => {
    const withNote = action === "decide" && body.decision === "approve" && !("note" in body)
      ? { ...body, note: "Checked it" }
      : body;
    return await lifecycle[action](caller, withNote, store) as Result;
  };
  return { store, run };
}

async function assertHttp(call: () => Promise<unknown>, status: number, code: string) {
  const error = await assertRejects(call, HttpError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}

// submit

Deno.test("submit: saved as pending under the caller, with a logged decision", async () => {
  const { store, run } = setup();
  const row = await run("submit", rider(), { route: route("r1") });
  assertEquals(row.status, "pending");
  assertEquals(row.revision, 1);
  assertEquals(row.contributor_id, "rider-1");
  assertEquals(row.contributor_name, "Rider One");
  assertEquals(store.decisions.map((d) => d.decision), ["submitted", "flagged"]);
});

Deno.test("submit: the app can't choose the owner or status", async () => {
  const { run } = setup();
  const row = await run("submit", rider(), {
    route: route("r1", {
      contributorId: "someone-else",
      contributorName: "Someone Else",
      approvalStatus: "approved",
      status: "published",
      views: 500,
      isEdited: true,
      editCount: 9,
    }),
  });
  assertEquals(row.status, "pending");
  assertEquals(row.contributor_id, "rider-1");
  assertEquals(row.contributor_name, "Rider One");
  assertEquals(row.views, 0);
  assertEquals(row.data.isEdited, false);
  assertEquals(row.data.editCount, 0);
});

Deno.test("submit: a blocked rider is refused", async () => {
  const { run } = setup();
  await assertHttp(() => run("submit", rider("r", true), { route: route("r1") }), 403, "blocked");
});

Deno.test("submit: a route with no usable id can't be stored", async () => {
  const { run } = setup();
  const bad = [
    undefined,
    "not an object",
    { startLocation: "A", endLocation: "B", steps: [{}] },
    route(""),
    route("x".repeat(129)),
  ];
  for (const candidate of bad) {
    await assertHttp(() => run("submit", rider(), { route: candidate }), 400, "invalid");
  }
});

Deno.test("submit: ids in the app's real format work", async () => {
  // The app uses DateTime.now().toString() as the id.
  const { run } = setup();
  const row = await run("submit", rider(), { route: route("2026-11-09 14:30:00.123456") });
  assertEquals(row.id, "2026-11-09 14:30:00.123456");
});

Deno.test("submit: a rider can't pass a route off as OpenStreetMap", async () => {
  const { run } = setup();
  await assertHttp(() => run("submit", rider(), { route: route("osm-fake") }), 400, "invalid");
});

Deno.test("submit: a 4th pending route is refused, and resending one is fine", async () => {
  const { store, run } = setup();
  for (const id of ["r1", "r2", "r3"]) await run("submit", rider(), { route: route(id) });
  await assertHttp(() => run("submit", rider(), { route: route("r4") }), 409, "pending_limit");
  const resent = await run("submit", rider(), { route: route("r2", { startLocation: "New" }) });
  assertEquals(resent.data.startLocation, "New");
  assertEquals(resent.revision, 1);
  assertEquals(await store.countPending("rider-1"), 3);
});

Deno.test("submit: resending keeps the real name, and the app can't change it", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const plain = await run("submit", rider(), { route: route("r1") });
  assertEquals(plain.contributor_name, "Rider One");
  const faked = await run("submit", rider(), { route: route("r1", { contributorName: "Someone Else" }) });
  assertEquals(faked.contributor_name, "Rider One");
});

Deno.test("submit: another rider's id is refused and their route stays", async () => {
  const { store, run } = setup();
  await run("submit", rider("owner"), { route: route("r1") });
  await assertHttp(() => run("submit", rider("thief"), { route: route("r1") }), 409, "conflict");
  assertEquals((await store.get("r1"))?.contributor_id, "owner");
});

Deno.test("submit: can't overwrite your own route that's already live", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("decide", moderator, { routeId: "r1", decision: "approve" });
  await assertHttp(() => run("submit", rider(), { route: route("r1") }), 409, "conflict");
});

// resubmit

Deno.test("resubmit: a rejected route goes back to pending with a new revision", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("decide", moderator, { routeId: "r1", decision: "reject", reasonCodes: ["wrong_fare"] });
  const row = await run("resubmit", rider(), { route: route("r1", { startLocation: "Fixed" }) });
  assertEquals(row.status, "pending");
  assertEquals(row.revision, 2);
  assertEquals(row.rejected_at, null);
  assertEquals(row.data.startLocation, "Fixed");
  assertEquals(store.decisions.at(-2)?.decision, "resubmitted");
  assertEquals(store.decisions.at(-2)?.revision, 2);
});

Deno.test("resubmit: marks the route as edited, like today's updateRoute", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const first = await run("resubmit", rider(), { route: route("r1", { editCount: 50, isEdited: false }) });
  assertEquals(first.data.isEdited, true);
  assertEquals(first.data.editCount, 1);
  assert(typeof first.data.editedAt === "string");
  const second = await run("resubmit", rider(), { route: route("r1") });
  assertEquals(second.data.editCount, 2);
});

Deno.test("resubmit: rebuilds the map line", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("resubmit", rider(), {
    route: route("r1", { pathPoints: [{ lat: 14.1, lng: 121.2 }, { lat: 14.3, lng: 121.4 }] }),
  });
  assertEquals((await store.get("r1"))?.geom, "SRID=4326;LINESTRING(121.2 14.1,121.4 14.3)");
});

Deno.test("resubmit: only the contributor or staff can", async () => {
  const { store, run } = setup();
  await run("submit", rider("owner"), { route: route("r1") });
  await assertHttp(() => run("resubmit", rider("other"), { route: route("r1") }), 403, "forbidden");
  const row = await run("resubmit", moderator, { route: route("r1") });
  assertEquals(row.contributor_id, "owner");
  assertEquals(store.decisions.at(-2)?.actor, "mod-1");
});

Deno.test("resubmit: a blocked contributor is refused", async () => {
  const { run } = setup();
  await run("submit", rider("owner"), { route: route("r1") });
  await assertHttp(() => run("resubmit", rider("owner", true), { route: route("r1") }), 403, "blocked");
});

Deno.test("resubmit: a route that doesn't exist gives 404", async () => {
  const { run } = setup();
  await assertHttp(() => run("resubmit", rider(), { route: route("none") }), 404, "not_found");
});

Deno.test("resubmit: can't bring back a rejected route past the pending limit", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("rejected") });
  await run("decide", moderator, { routeId: "rejected", decision: "reject", reasonCodes: ["duplicate"] });
  for (const id of ["r1", "r2", "r3"]) await run("submit", rider(), { route: route(id) });
  await assertHttp(() => run("resubmit", rider(), { route: route("rejected") }), 409, "pending_limit");
  // Editing one that's already waiting doesn't add to the count.
  const edited = await run("resubmit", rider(), { route: route("r1") });
  assertEquals(edited.revision, 2);
});

Deno.test("resubmit: can't turn a route into a correction of another one", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const row = await run("resubmit", rider(), { route: route("r1", { correctionOf: "someone-elses-route" }) });
  assertEquals(row.correction_of, null);
  assertEquals(row.data.correctionOf, undefined);
});

Deno.test("resubmit: staff edits keep a closed account's Former rider label", async () => {
  const { store, run } = setup();
  await run("submit", rider("owner"), { route: route("r1") });
  await run("decide", moderator, { routeId: "r1", decision: "approve" });
  await run("close_account", rider("owner"));
  await run("resubmit", moderator, { route: route("r1") });
  const row = await store.get("r1");
  assertEquals(row?.contributor_name, "Former rider");
  assertEquals(row?.data.contributorClosed, true);
});

// Lists

Deno.test("my_routes: own routes at any status, with the latest reasons", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("submit", rider(), { route: route("r2") });
  await run("submit", rider("other"), { route: route("r3") });
  await run("decide", moderator, {
    routeId: "r1",
    decision: "reject",
    reasonCodes: ["wrong_fare"],
    note: "The fare is ₱13",
  });
  const rows = await run("my_routes", rider()) as unknown as RouteRow[];
  assertEquals(rows.map((r) => r.id).sort(), ["r1", "r2"]);
  const rejected = rows.find((r) => r.id === "r1");
  assertEquals(rejected?.status, "rejected");
  assertEquals(rejected?.latest_decision?.reason_codes, ["wrong_fare"]);
  assertEquals(rejected?.latest_decision?.note, "The fare is ₱13");
});

Deno.test("queue: the route that has waited longest comes first", async () => {
  const { store, run } = setup();
  for (const id of ["new", "old", "middle"]) await run("submit", rider(), { route: route(id, { startLocation: `Start ${id}` }) });
  // Put each route's queue entry at a different time.
  const daysAgo = (n: number) => new Date(Date.now() - n * 86400000).toISOString();
  const when: Record<string, string> = { new: daysAgo(1), old: daysAgo(9), middle: daysAgo(4) };
  for (const decision of store.decisions) decision.created_at = when[decision.route_id];
  const queue = await run("queue", moderator) as unknown as RouteRow[];
  assertEquals(queue.map((r) => r.id), ["old", "middle", "new"]);
});

Deno.test("queue and staff_list: staff only", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("submit", rider(), { route: route("r2") });
  await run("decide", moderator, { routeId: "r2", decision: "approve" });
  await assertHttp(() => run("queue", rider()), 403, "forbidden");
  await assertHttp(() => run("staff_list", rider()), 403, "forbidden");
  const queue = await run("queue", moderator) as unknown as RouteRow[];
  assertEquals(queue.map((r) => r.id), ["r1"]);
  assertEquals(queue[0].latest_decision?.decision, "flagged");
  const all = await run("staff_list", moderator) as unknown as RouteRow[];
  assertEquals(all.map((r) => r.id).sort(), ["r1", "r2"]);
});

// decide

Deno.test("decide: riders and blocked staff are refused", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const body = { routeId: "r1", decision: "approve" };
  await assertHttp(() => run("decide", rider(), body), 403, "forbidden");
  await assertHttp(() => run("decide", { ...moderator, blocked: true }, body), 403, "blocked");
});

Deno.test("decide: bad requests are refused", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await assertHttp(() => run("decide", moderator, { decision: "approve" }), 400, "invalid");
  await assertHttp(() => run("decide", moderator, { routeId: "r1", decision: "maybe" }), 400, "invalid");
  await assertHttp(() => run("decide", moderator, { routeId: "none", decision: "approve" }), 404, "not_found");
});

Deno.test("approve: published and verified, and clears the edit flags", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("resubmit", rider(), { route: route("r1", { staleNeedsReview: true }) });
  const result = await run("decide", moderator, { routeId: "r1", decision: "approve" });
  assertEquals(result.route.status, "published");
  assertEquals(result.route.verification, "verified");
  assert(result.route.published_at);
  assertEquals(result.route.data.isEdited, false);
  assertEquals(result.route.data.staleNeedsReview, false);
  assertEquals(result.contributorId, "rider-1");
  assertEquals(result.title, "Monumento to Malabon");
  assertEquals(result.mergedInto, undefined);
  assertEquals(store.decisions.at(-1)?.decision, "approved");
  assertEquals(store.decisions.at(-1)?.actor, "mod-1");
});

Deno.test("approve twice: the second is a conflict and logs nothing", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("decide", moderator, { routeId: "r1", decision: "approve" });
  const logged = store.decisions.length;
  await assertHttp(() => run("decide", moderator, { routeId: "r1", decision: "approve" }), 409, "conflict");
  assertEquals(store.decisions.length, logged);
});

Deno.test("decide: two moderators at the same moment, only one wins", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const results = await Promise.allSettled([
    run("decide", moderator, { routeId: "r1", decision: "approve" }),
    run("decide", superadmin, { routeId: "r1", decision: "reject", reasonCodes: ["duplicate"] }),
  ]);
  assertEquals(results.filter((r) => r.status === "fulfilled").length, 1);
  assertEquals(store.decisions.filter((d) => d.decision === "approved" || d.decision === "rejected").length, 1);
});

Deno.test("reject: needs at least one known reason", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const reject = (extra: Record<string, unknown>) =>
    run("decide", moderator, { routeId: "r1", decision: "reject", ...extra });
  await assertHttp(() => reject({}), 400, "invalid");
  await assertHttp(() => reject({ reasonCodes: [] }), 400, "invalid");
  await assertHttp(() => reject({ reasonCodes: "wrong_fare" }), 400, "invalid");
  await assertHttp(() => reject({ reasonCodes: ["made_up"] }), 400, "invalid");
  assertEquals((await store.get("r1"))?.status, "pending");
});

Deno.test("reject: Other needs a real note", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const reject = (extra: Record<string, unknown>) =>
    run("decide", moderator, { routeId: "r1", decision: "reject", reasonCodes: ["other"], ...extra });
  await assertHttp(() => reject({}), 400, "invalid");
  await assertHttp(() => reject({ note: "   " }), 400, "invalid");
  const result = await reject({ note: " Not a real terminal " });
  assertEquals(result.route.status, "rejected");
});

Deno.test("reject: the route is kept, with its reasons logged", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  const result = await run("decide", moderator, {
    routeId: "r1",
    decision: "reject",
    reasonCodes: ["wrong_fare", "wrong_path"],
    note: "Check the fare",
  });
  assertEquals(result.route.status, "rejected");
  assert(result.route.rejected_at);
  assertEquals(result.route.data.pathPoints, route("r1").pathPoints);
  const log = store.decisions.at(-1);
  assertEquals(log?.decision, "rejected");
  assertEquals(log?.reason_codes, ["wrong_fare", "wrong_path"]);
  assertEquals(log?.note, "Check the fare");
});

// Corrections

async function correctionSetup() {
  const { store, run } = setup();
  await run("submit", rider("owner"), {
    route: route("target", { eta: "10 min", steps: [{ mode: "Bus" }], shortDescription: "Keep me" }),
  });
  await run("decide", moderator, { routeId: "target", decision: "approve" });
  await run("submit", rider("fixer"), {
    route: route("fix", {
      correctionOf: "target",
      eta: "20 min",
      steps: [{ mode: "Jeepney" }],
      shortDescription: "Don't copy me",
      pathPoints: [{ lat: 14.1, lng: 121.2 }, { lat: 14.12, lng: 121.22 }],
    }),
  });
  return { store, run };
}

Deno.test("approve correction: merged into the target, and the correction is gone", async () => {
  const { store, run } = await correctionSetup();
  const result = await run("decide", moderator, { routeId: "fix", decision: "approve" });
  const target = await store.get("target");
  assertEquals(result.mergedInto, "target");
  assertEquals(target?.data.steps, [{ mode: "Jeepney" }]);
  assertEquals(target?.data.eta, "20 min");
  assertEquals(target?.data.editCount, 1);
  assertEquals(target?.geom, "SRID=4326;LINESTRING(121.2 14.1,121.22 14.12)");
  // Only the listed keys change. The owner, description and votes stay.
  assertEquals(target?.data.shortDescription, "Keep me");
  assertEquals(target?.contributor_id, "owner");
  assertEquals(target?.status, "published");
  assertEquals(await store.get("fix"), null);
  // The person to notify is whoever sent the correction.
  assertEquals(result.contributorId, "fixer");
  const log = store.decisions.at(-1);
  assertEquals(log?.route_id, "target");
  assertEquals(log?.note, "correction fix by fixer merged: Checked it");
});

Deno.test("approve correction: if the target is gone, it becomes its own route", async () => {
  const { store, run } = await correctionSetup();
  await store.remove("target");
  const result = await run("decide", moderator, { routeId: "fix", decision: "approve" });
  assertEquals(result.mergedInto, undefined);
  assertEquals(result.route.status, "published");
});

Deno.test("approve correction: a GTFS correction becomes its own route", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("fix", { correctionOf: "gtfs:LTFRB_1" }) });
  const result = await run("decide", moderator, { routeId: "fix", decision: "approve" });
  assertEquals(result.mergedInto, undefined);
  assertEquals(result.route.correction_of, "gtfs:LTFRB_1");
});

Deno.test("approve correction: a failed merge leaves the correction pending to retry", async () => {
  const { store, run } = await correctionSetup();
  const realUpdate = store.update.bind(store);
  store.update = (id, patch, onlyIfStatus) =>
    id === "target" ? Promise.reject(new Error("database hiccup")) : realUpdate(id, patch, onlyIfStatus);
  await assertRejects(() => run("decide", moderator, { routeId: "fix", decision: "approve" }), Error, "database hiccup");
  store.update = realUpdate;
  assertEquals((await store.get("fix"))?.status, "pending");
  const retried = await run("decide", moderator, { routeId: "fix", decision: "approve" });
  assertEquals(retried.mergedInto, "target");
});

// Moderator approval counts

Deno.test("moderator_approvals: superadmin only", async () => {
  const { run } = setup();
  await assertHttp(() => run("moderator_approvals", rider()), 403, "forbidden");
  await assertHttp(() => run("moderator_approvals", moderator), 403, "forbidden");
});

Deno.test("moderator_approvals: per moderator, with re-approvals counted once", async () => {
  const { run } = await correctionSetup();
  await run("decide", superadmin, { routeId: "fix", decision: "approve" });
  await run("submit", rider(), { route: route("r2") });
  await run("decide", superadmin, { routeId: "r2", decision: "approve" });
  await run("resubmit", rider(), { route: route("r2") });
  await run("decide", superadmin, { routeId: "r2", decision: "approve" });
  await run("submit", rider(), { route: route("r3") });
  await run("decide", superadmin, { routeId: "r3", decision: "reject", reasonCodes: ["duplicate"] });

  const result = await run("moderator_approvals", superadmin) as unknown as Record<string, string[]>;

  // mod-1 approved "target". admin-1 merged a correction and approved r2 twice.
  assertEquals(result["mod-1"], ["target|Checked it"]);
  assertEquals(
    [...result["admin-1"]].sort(),
    ["r2|Checked it", "target|correction fix by fixer merged: Checked it"],
  );
});

// delete and close_account

Deno.test("delete: a rider deletes their own pending or rejected route", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("waiting") });
  await run("submit", rider(), { route: route("turned_down", { startLocation: "Start 2" }) });
  await run("decide", moderator, { routeId: "turned_down", decision: "reject", reasonCodes: ["duplicate"] });
  for (const id of ["waiting", "turned_down"]) {
    await run("delete", rider(), { routeId: id });
    assertEquals(await store.get(id), null, id);
    assertEquals(store.decisions.at(-1)?.decision, "withdrawn");
    assertEquals(store.decisions.at(-1)?.actor, "rider-1");
  }
});

Deno.test("delete: a rider can't delete a live route, or anyone else's", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("live") });
  await run("decide", moderator, { routeId: "live", decision: "approve" });
  await assertHttp(() => run("delete", rider(), { routeId: "live" }), 403, "forbidden");
  assertEquals((await store.get("live"))?.status, "published");
  await run("submit", rider("other"), { route: route("theirs", { startLocation: "Start 3" }) });
  await assertHttp(() => run("delete", rider(), { routeId: "theirs" }), 403, "forbidden");
  assert(await store.get("theirs"));
});

Deno.test("delete: a deleted pending route frees a slot", async () => {
  const { run } = setup();
  for (const id of ["p1", "p2", "p3"]) await run("submit", rider(), { route: route(id, { startLocation: `Start ${id}` }) });
  await assertHttp(() => run("submit", rider(), { route: route("p4", { startLocation: "Start p4" }) }), 409, "pending_limit");
  await run("delete", rider(), { routeId: "p1" });
  const row = await run("submit", rider(), { route: route("p4", { startLocation: "Start p4" }) });
  assertEquals(row.status, "pending");
});

Deno.test("delete: anyone else's route is superadmin only", async () => {
  const { store, run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await assertHttp(() => run("delete", moderator, { routeId: "r1" }), 403, "forbidden");
  assert(await store.get("r1"));
  await run("delete", superadmin, { routeId: "r1" });
  assertEquals(await store.get("r1"), null);
  assertEquals(store.decisions.at(-1)?.decision, "deleted");
  await assertHttp(() => run("delete", superadmin, { routeId: "r1" }), 404, "not_found");
});

Deno.test("close_account: unpublished routes go, live ones become Former rider", async () => {
  const { store, run } = setup();
  await run("submit", rider("leaver"), { route: route("live") });
  await run("decide", moderator, { routeId: "live", decision: "approve" });
  await run("submit", rider("leaver"), { route: route("waiting") });
  await run("submit", rider("leaver"), { route: route("refused") });
  await run("decide", moderator, { routeId: "refused", decision: "reject", reasonCodes: ["duplicate"] });
  await run("submit", rider("stays"), { route: route("theirs") });

  const result = await run("close_account", rider("leaver")) as unknown as { released: number; removed: number };
  assertEquals(result, { released: 1, removed: 2 });

  const live = await store.get("live");
  assertEquals(live?.contributor_id, null);
  assertEquals(live?.contributor_name, "Former rider");
  assertEquals(live?.data.contributorClosed, true);
  assertEquals(live?.status, "published");
  assertEquals(await store.get("waiting"), null);
  assertEquals(await store.get("refused"), null);
  assertEquals((await store.get("theirs"))?.contributor_id, "stays");
});

Deno.test("close_account: a banned rider can still close their account", async () => {
  const { store, run } = setup();
  await run("submit", rider("leaver"), { route: route("waiting") });
  await run("close_account", rider("leaver", true));
  assertEquals(await store.get("waiting"), null);
});

// The checklist

const OLD_ACCOUNT = new Date(Date.now() - 30 * 86400000).toISOString();

// Close enough points that the line counts as following the road.
const SHORT_PATH = [{ lat: 14.65, lng: 120.98 }, { lat: 14.652, lng: 120.98 }];
const cleanRoute = (id: string, extra: Record<string, unknown> = {}) =>
  route(id, { pathPoints: SHORT_PATH, stepBoundaries: [1], steps: [{ mode: "Jeepney", instruction: "Ride", actualFare: 14 }], ...extra });
const expensive = [{ mode: "Jeepney", instruction: "Ride", actualFare: 500 }];

// Someone with an old account and a published route, so nothing flags them.
async function knownRider(harness: ReturnType<typeof setup>) {
  const caller = { ...rider("known"), createdAt: OLD_ACCOUNT };
  await harness.run("submit", caller, { route: cleanRoute("first") });
  await harness.run("decide", moderator, { routeId: "first", decision: "approve" });
  return caller;
}

type Outcome = Result & { outcome: string; appliedTo?: string; checks: { code: string; result: string }[] };

Deno.test("checklist: all pass goes live right away, as Unverified", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  const row = await harness.run("submit", caller, { route: cleanRoute("r2") }) as Outcome;
  assertEquals(row.outcome, "published");
  assertEquals(row.status, "published");
  assertEquals(row.verification, "unverified");
  assert(row.published_at);
  const log = harness.store.decisions.at(-1);
  assertEquals(log?.decision, "auto_published");
  assertEquals(log?.actor, "system");
});

Deno.test("checklist: a soft fail waits for a moderator, with the flags on record", async () => {
  const harness = setup();
  const row = await harness.run("submit", rider(), { route: cleanRoute("r1") }) as Outcome;
  assertEquals(row.outcome, "pending");
  assertEquals(row.status, "pending");
  const log = harness.store.decisions.at(-1);
  assertEquals(log?.decision, "flagged");
  assertEquals(log?.actor, "system");
  assertEquals(log?.reason_codes, ["S_NEW_CONTRIBUTOR"]);
});

Deno.test("checklist: a hard fail is rejected right away, kept, and says why", async () => {
  const harness = setup();
  const row = await harness.run("submit", rider(), { route: cleanRoute("r1", { steps: expensive }) }) as Outcome;
  assertEquals(row.outcome, "rejected");
  assertEquals(row.status, "rejected");
  assert(row.rejected_at);
  assertEquals(row.data.pathPoints, SHORT_PATH);
  const log = harness.store.decisions.at(-1);
  assertEquals(log?.decision, "auto_rejected");
  assertEquals(log?.actor, "system");
  assertEquals(log?.reason_codes, ["H_FARE_IMPOSSIBLE"]);
});

Deno.test("checklist: missing details are a stored rejection, not an error", async () => {
  const harness = setup();
  const row = await harness.run("submit", rider(), { route: route("r1", { steps: [] }) }) as Outcome;
  assertEquals(row.outcome, "rejected");
  assertEquals(row.checks.find((c) => c.code === "H_REQUIRED")?.result, "fail");
});

Deno.test("checklist: results come back and show in the lists", async () => {
  const harness = setup();
  const row = await harness.run("submit", rider(), { route: cleanRoute("r1") }) as Outcome;
  assertEquals(row.checks.find((c) => c.code === "S_NEW_CONTRIBUTOR")?.result, "flag");
  const queue = await harness.run("queue", moderator) as unknown as RouteRow[];
  assertEquals((queue[0].latest_checks as { code: string }[]).some((c) => c.code === "S_NEW_CONTRIBUTOR"), true);
  const mine = await harness.run("my_routes", rider()) as unknown as RouteRow[];
  assertEquals((mine[0].latest_checks ?? []).length > 0, true);
});

Deno.test("checklist: lists show only the current revision's checks", async () => {
  const harness = setup();
  await harness.run("submit", rider(), { route: cleanRoute("r1", { steps: expensive }) });
  await harness.run("resubmit", rider(), { route: cleanRoute("r1") });
  const mine = await harness.run("my_routes", rider()) as unknown as RouteRow[];
  const fare = (mine[0].latest_checks as { code: string; result: string }[]).find((c) => c.code === "H_FARE_IMPOSSIBLE");
  assertEquals(fare?.result, "pass");
});

Deno.test("checklist: if the map lookup fails, the route waits for a moderator", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  harness.store.factsError = new Error("database down");
  const row = await harness.run("submit", caller, { route: cleanRoute("r2") }) as Outcome;
  assertEquals(row.outcome, "pending");
});

Deno.test("checklist: if the fare table fails, the route waits for a moderator", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  harness.store.rules = new Error("database down");
  const row = await harness.run("submit", caller, { route: cleanRoute("r2") }) as Outcome;
  assertEquals(row.outcome, "pending");
});

Deno.test("checklist: fixing a rejected route can publish it, and clears the edit flag", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  await harness.run("submit", caller, { route: cleanRoute("r2", { steps: expensive }) });
  const fixed = await harness.run("resubmit", caller, { route: cleanRoute("r2") }) as Outcome;
  assertEquals(fixed.outcome, "published");
  assertEquals(fixed.revision, 2);
  assertEquals(fixed.rejected_at, null);
  assertEquals(fixed.data.isEdited, false);
});

Deno.test("checklist: an edit can get a live route rejected, and it stops being live", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  await harness.run("submit", caller, { route: cleanRoute("r2") });
  const row = await harness.run("resubmit", caller, { route: cleanRoute("r2", { steps: expensive }) }) as Outcome;
  assertEquals(row.status, "rejected");
});

Deno.test("checklist: the pending limit only counts routes joining the queue", async () => {
  const harness = setup();
  for (const id of ["r1", "r2", "r3"]) await harness.run("submit", rider(), { route: cleanRoute(id) });
  await assertHttp(() => harness.run("submit", rider(), { route: cleanRoute("r4") }), 409, "pending_limit");
  // A rejected route doesn't join the queue, so it still gets its reasons.
  const row = await harness.run("submit", rider(), { route: cleanRoute("r5", { steps: expensive }) }) as Outcome;
  assertEquals(row.outcome, "rejected");
});

Deno.test("checklist: the map lookup gets the route's real details", async () => {
  const harness = setup();
  await harness.run("submit", rider(), { route: cleanRoute("r1", { correctionOf: "t9" }) });
  const asked = harness.store.lastFactsRequest;
  assertEquals(asked?.routeId, "r1");
  assertEquals(asked?.contributorId, "rider-1");
  assertEquals(asked?.correctionOf, "t9");
  assert(asked?.geom?.startsWith("SRID=4326;LINESTRING"));
});

Deno.test("checklist: an edit can't change what the lookup thinks it corrects", async () => {
  const harness = setup();
  await harness.run("submit", rider(), { route: cleanRoute("r1") });
  await harness.run("resubmit", rider(), { route: cleanRoute("r1", { correctionOf: "someone-elses" }) });
  assertEquals(harness.store.lastFactsRequest?.correctionOf, null);
});

Deno.test("checklist: staff edits and submissions never publish themselves", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  await harness.run("submit", caller, { route: cleanRoute("r2") });
  const edited = await harness.run("resubmit", moderator, { route: cleanRoute("r2") }) as Outcome;
  assertEquals(edited.outcome, "pending");
  const staff = { ...moderator, createdAt: OLD_ACCOUNT };
  const own = await harness.run("submit", staff, { route: cleanRoute("osm-new") }) as Outcome;
  assertEquals(own.outcome, "pending");
});

Deno.test("checklist: staff can't save a route that fails a hard check", async () => {
  const harness = setup();
  await harness.run("submit", rider(), { route: cleanRoute("r1") });
  const row = await harness.run("resubmit", moderator, { route: cleanRoute("r1", { steps: expensive }) }) as Outcome;
  assertEquals(row.status, "rejected");
});

// Approving over a flag

Deno.test("approve: over a flag needs a note, and it goes on record", async () => {
  const harness = setup();
  await harness.run("submit", rider(), { route: cleanRoute("r1") });
  const approve = (extra: Record<string, unknown>) =>
    harness.run("decide", moderator, { routeId: "r1", decision: "approve", ...extra });
  await assertHttp(() => approve({ note: "" }), 400, "note_required");
  await assertHttp(() => approve({ note: "   " }), 400, "note_required");
  assertEquals((await harness.store.get("r1"))?.status, "pending");
  await approve({ note: "New rider but the route is real" });
  assertEquals(harness.store.decisions.at(-1)?.note, "New rider but the route is real");
});

Deno.test("approve: a route with no flags needs no note", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  await harness.run("submit", caller, { route: cleanRoute("r2") });
  await harness.run("resubmit", moderator, { route: cleanRoute("r2") });
  assertEquals((await harness.store.get("r2"))?.status, "pending");
  await lifecycle.decide(moderator, { routeId: "r2", decision: "approve" }, harness.store);
  assertEquals((await harness.store.get("r2"))?.verification, "verified");
});

// Verifying

Deno.test("verify: staff can vouch for a live route, and take it back", async () => {
  const harness = setup();
  const caller = await knownRider(harness);
  await harness.run("submit", caller, { route: cleanRoute("r2") });
  await harness.run("decide", moderator, { routeId: "r2", decision: "verify" });
  assertEquals((await harness.store.get("r2"))?.verification, "verified");
  assertEquals(harness.store.decisions.at(-1)?.decision, "verified");
  await harness.run("decide", moderator, { routeId: "r2", decision: "unverify" });
  const row = await harness.store.get("r2");
  assertEquals(row?.verification, "unverified");
  assertEquals(row?.status, "published");
});

Deno.test("verify: only live routes, and only staff", async () => {
  const harness = setup();
  await harness.run("submit", rider(), { route: cleanRoute("r1") });
  await assertHttp(() => harness.run("decide", moderator, { routeId: "r1", decision: "verify" }), 409, "conflict");
  await assertHttp(() => harness.run("decide", rider(), { routeId: "r1", decision: "verify" }), 403, "forbidden");
});

// Fare-only corrections

async function fareSetup() {
  const harness = setup();
  const caller = await knownRider(harness);
  harness.store.facts = { ...harness.store.facts, target_exists: true, target_status: "published", correction_kept: 1 };
  return { ...harness, caller };
}
const fareFix = (fare: number, extra: Record<string, unknown> = {}) =>
  cleanRoute("fix", { correctionOf: "first", price: `PHP ${fare}`, steps: [{ mode: "Jeepney", instruction: "Ride", actualFare: fare }], ...extra });

Deno.test("fare correction: in range is applied to the route by itself", async () => {
  const { store, run, caller } = await fareSetup();
  const result = await run("submit", caller, { route: fareFix(15) }) as Outcome;
  assertEquals(result.outcome, "applied");
  assertEquals(result.appliedTo, "first");
  const target = await store.get("first");
  assertEquals((target?.data.steps as { actualFare: number }[])[0].actualFare, 15);
  assertEquals(target?.data.price, "PHP 15");
  assertEquals(target?.data.editCount, 1);
  assertEquals(await store.get("fix"), null);
  const log = store.decisions.at(-1);
  assertEquals(log?.decision, "auto_published");
  assertEquals(log?.actor, "system");
  assertEquals(log?.route_id, "first");
});

Deno.test("fare correction: out of range goes to a moderator instead", async () => {
  const { store, run, caller } = await fareSetup();
  const result = await run("submit", caller, { route: fareFix(30) }) as Outcome;
  assertEquals(result.outcome, "pending");
  assertEquals((await store.get("first"))?.data.steps, cleanRoute("x").steps);
});

Deno.test("fare correction: changing anything else isn't automatic", async () => {
  const { store, run, caller } = await fareSetup();
  const moved = fareFix(15, { pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.651, lng: 120.98 }] });
  const result = await run("submit", caller, { route: moved }) as Outcome;
  assertEquals(result.outcome === "applied", false);
  assertEquals((await store.get("first"))?.data.pathPoints, SHORT_PATH);
});

// Fare rules

Deno.test("fare rules: superadmin only", async () => {
  const { run } = setup();
  await assertHttp(() => run("admin_fare_rules", moderator), 403, "forbidden");
  await assertHttp(
    () => run("admin_set_fare_rule", moderator, { mode: "jeepney", base: 15, base_km: 4, per_km: 2, source: "MC" }),
    403,
    "forbidden",
  );
});

Deno.test("fare rules: bad values are refused, good ones saved", async () => {
  const { run } = setup();
  const good = { mode: "jeepney", base: 15, base_km: 4, per_km: 2, source: "LTFRB MC 2026-01" };
  for (const bad of [
    { ...good, mode: "helicopter" },
    { ...good, base: 0 },
    { ...good, base: "15" },
    { ...good, base_km: -1 },
    { ...good, per_km: -1 },
    { ...good, source: " " },
    { ...good, effective_from: "not a date" },
  ]) {
    await assertHttp(() => run("admin_set_fare_rule", superadmin, bad), 400, "invalid");
  }
  await run("admin_set_fare_rule", superadmin, good);
  const rules = await run("admin_fare_rules", superadmin) as unknown as { source: string }[];
  assertEquals(rules[0].source, "LTFRB MC 2026-01");
});
