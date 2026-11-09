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
});
const moderator: Caller = { uid: "mod-1", role: "moderator", blocked: false, name: "Mod" };
const superadmin: Caller = { uid: "admin-1", role: "superadmin", blocked: false, name: "Admin" };

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
  const run = async (action: string, caller: Caller, body: Record<string, unknown> = {}) =>
    await lifecycle[action](caller, body, store) as Result;
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
  assertEquals(store.decisions.map((d) => d.decision), ["submitted"]);
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

Deno.test("submit: incomplete routes are refused", async () => {
  const { run } = setup();
  const bad = [
    undefined,
    "not an object",
    { startLocation: "A", endLocation: "B", steps: [{}] }, // no id
    route(""),
    route("x".repeat(129)),
    route("r1", { steps: [] }),
    route("r1", { steps: "junk" }),
    route("r1", { startLocation: "  " }),
    route("r1", { endLocation: undefined }),
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
  assertEquals(store.decisions.at(-1)?.decision, "resubmitted");
  assertEquals(store.decisions.at(-1)?.revision, 2);
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
    route: route("r1", { pathPoints: [{ lat: 1, lng: 2 }, { lat: 3, lng: 4 }] }),
  });
  assertEquals((await store.get("r1"))?.geom, "SRID=4326;LINESTRING(2 1,4 3)");
});

Deno.test("resubmit: only the contributor or staff can", async () => {
  const { store, run } = setup();
  await run("submit", rider("owner"), { route: route("r1") });
  await assertHttp(() => run("resubmit", rider("other"), { route: route("r1") }), 403, "forbidden");
  const row = await run("resubmit", moderator, { route: route("r1") });
  assertEquals(row.contributor_id, "owner");
  assertEquals(store.decisions.at(-1)?.actor, "mod-1");
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

Deno.test("queue and staff_list: staff only", async () => {
  const { run } = setup();
  await run("submit", rider(), { route: route("r1") });
  await run("submit", rider(), { route: route("r2") });
  await run("decide", moderator, { routeId: "r2", decision: "approve" });
  await assertHttp(() => run("queue", rider()), 403, "forbidden");
  await assertHttp(() => run("staff_list", rider()), 403, "forbidden");
  const queue = await run("queue", moderator) as unknown as RouteRow[];
  assertEquals(queue.map((r) => r.id), ["r1"]);
  assertEquals(queue[0].latest_decision?.decision, "submitted");
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
  assertEquals(store.decisions.filter((d) => d.decision !== "submitted").length, 1);
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
      pathPoints: [{ lat: 1, lng: 2 }, { lat: 3, lng: 4 }],
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
  assertEquals(target?.geom, "SRID=4326;LINESTRING(2 1,4 3)");
  // Only the listed keys change. The owner, description and votes stay.
  assertEquals(target?.data.shortDescription, "Keep me");
  assertEquals(target?.contributor_id, "owner");
  assertEquals(target?.status, "published");
  assertEquals(await store.get("fix"), null);
  // The person to notify is whoever sent the correction.
  assertEquals(result.contributorId, "fixer");
  const log = store.decisions.at(-1);
  assertEquals(log?.route_id, "target");
  assertEquals(log?.note, "correction fix by fixer merged");
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
  assertEquals(result["mod-1"], ["target"]);
  assertEquals(
    [...result["admin-1"]].sort(),
    ["r2", "target|correction fix by fixer merged"],
  );
});

// delete and close_account

Deno.test("delete: superadmin only", async () => {
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
