import { assert, assertEquals, assertRejects } from "jsr:@std/assert@^1.0.0";
import { lifecycle } from "./actions/lifecycle.ts";
import { reports, reviewReports } from "./actions/reports.ts";
import type { Caller } from "./caller.ts";
import { HttpError } from "./http.ts";
import type { Issue } from "./reports.ts";
import type { RouteRow } from "./rows.ts";
import { MemoryStore } from "./store_memory.ts";

const rider = (uid = "rider-1", blocked = false): Caller => ({
  uid,
  role: "rider",
  blocked,
  name: uid,
  createdAt: null,
});
const moderator: Caller = { uid: "mod-1", role: "moderator", blocked: false, name: "Mod", createdAt: null };

// About 1.6 km, so the usual jeepney fare is ₱14 and ₱12 to ₱16 passes.
const routeData = (extra: Record<string, unknown> = {}) => ({
  startLocation: "Monumento",
  endLocation: "Malabon",
  steps: [{ mode: "Jeepney", instruction: "Ride", actualFare: 13 }],
  pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.66, lng: 120.99 }],
  price: "PHP 13",
  ...extra,
});

async function seedRoute(store: MemoryStore, id = "r1", extra: Partial<RouteRow> = {}) {
  return await store.insert({
    id,
    source: "rider",
    contributor_id: "owner",
    contributor_name: "Owner",
    correction_of: null,
    data: routeData(),
    status: "published",
    verification: "unverified",
    ...extra,
  });
}

function setup() {
  const store = new MemoryStore();
  const report = async (caller: Caller, body: Record<string, unknown>) =>
    await reports.report_issue(caller, body, store) as { id: number; outdated: boolean; fareChanged: boolean };
  return { store, report };
}

async function assertHttp(call: () => Promise<unknown>, status: number, code: string) {
  const error = await assertRejects(call, HttpError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}

const daysAgo = (days: number) => new Date(Date.now() - days * 86400000).toISOString();

// report_issue

Deno.test("report_issue: saves a report under the caller", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  const result = await report(rider(), { routeId: "r1", type: "wrong_stop", note: " Moved to the corner " });
  assertEquals(result.outdated, false);
  assertEquals(store.issues.length, 1);
  assertEquals(store.issues[0].reporter_id, "rider-1");
  assertEquals(store.issues[0].note, "Moved to the corner");
});

Deno.test("report_issue: refuses bad input", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  await assertHttp(() => report(rider(), { routeId: "r1", type: "broken" }), 400, "invalid");
  await assertHttp(() => report(rider(), { routeId: "", type: "wrong_stop" }), 400, "invalid");
  await assertHttp(() => report(rider(), { routeId: "r1", type: "other" }), 400, "invalid");
  await assertHttp(() => report(rider(), { routeId: "r1", type: "wrong_stop", note: "x".repeat(501) }), 400, "invalid");
  await assertHttp(() => report(rider(), { routeId: "r1", type: "wrong_fare" }), 400, "invalid");
  await assertHttp(() => report(rider(), { routeId: "r1", type: "wrong_fare", farePaid: -5 }), 400, "invalid");
  await assertHttp(() => report(rider(), { routeId: "r1", type: "wrong_fare", farePaid: 5000 }), 400, "invalid");
});

Deno.test("report_issue: only live routes, and not by banned riders", async () => {
  const { store, report } = setup();
  await seedRoute(store, "waiting", { status: "pending" });
  await assertHttp(() => report(rider(), { routeId: "missing", type: "wrong_stop" }), 404, "not_found");
  await assertHttp(() => report(rider(), { routeId: "waiting", type: "wrong_stop" }), 409, "not_live");
  await seedRoute(store);
  await assertHttp(() => report(rider("bad", true), { routeId: "r1", type: "wrong_stop" }), 403, "blocked");
});

Deno.test("report_issue: one open report per rider, route and type", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  await report(rider(), { routeId: "r1", type: "wrong_stop" });
  await assertHttp(() => report(rider(), { routeId: "r1", type: "wrong_stop" }), 409, "already_reported");
  // A different type is a different report.
  await report(rider(), { routeId: "r1", type: "wrong_schedule" });
});

Deno.test("report_issue: at most 20 a day per rider", async () => {
  const { store, report } = setup();
  for (let i = 0; i < 20; i++) {
    await seedRoute(store, `r${i}`);
    await report(rider(), { routeId: `r${i}`, type: "wrong_stop" });
  }
  await seedRoute(store, "r20");
  await assertHttp(() => report(rider(), { routeId: "r20", type: "wrong_stop" }), 429, "report_limit");
});

Deno.test("report_issue: GTFS routes can be reported if they're in the feed", async () => {
  const { store, report } = setup();
  store.gtfsNames.set("ROUTE_1", "Monumento - Navotas");
  await report(rider(), { routeId: "gtfs:ROUTE_1", type: "not_operating" });
  await assertHttp(() => report(rider(), { routeId: "gtfs:NOPE", type: "not_operating" }), 404, "not_found");
  // A fare report on a GTFS route needs no step.
  await report(rider(), { routeId: "gtfs:ROUTE_1", type: "wrong_fare", farePaid: 20 });
  assertEquals(store.issues[1].step_index, null);
});

Deno.test("report_issue: a fare report says which ride when there's more than one", async () => {
  const { store, report } = setup();
  await seedRoute(store, "two", {
    data: routeData({ steps: [{ mode: "Jeepney" }, { mode: "Walk" }, { mode: "Bus" }] }),
  });
  await assertHttp(() => report(rider(), { routeId: "two", type: "wrong_fare", farePaid: 20 }), 400, "invalid");
  // A walk isn't a ride.
  await assertHttp(
    () => report(rider(), { routeId: "two", type: "wrong_fare", farePaid: 20, stepIndex: 1 }),
    400,
    "invalid",
  );
  await report(rider(), { routeId: "two", type: "wrong_fare", farePaid: 20, stepIndex: 2 });
  assertEquals(store.issues[0].step_index, 2);
});

Deno.test("report_issue: a drawn fix must be the rider's own correction of this route", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  await seedRoute(store, "fix-mine", { status: "pending", contributor_id: "rider-1", correction_of: "r1" });
  await seedRoute(store, "fix-other", { status: "pending", contributor_id: "rider-2", correction_of: "r1" });
  await seedRoute(store, "fix-elsewhere", { status: "pending", contributor_id: "rider-1", correction_of: "r9" });
  await assertHttp(
    () => report(rider(), { routeId: "r1", type: "wrong_path", correctionId: "fix-other" }),
    400,
    "invalid",
  );
  await assertHttp(
    () => report(rider(), { routeId: "r1", type: "wrong_path", correctionId: "fix-elsewhere" }),
    400,
    "invalid",
  );
  await report(rider(), { routeId: "r1", type: "wrong_path", correctionId: "fix-mine" });
  assertEquals(store.issues[0].correction_id, "fix-mine");
});

// Possibly outdated

Deno.test("five riders make a route possibly outdated, and it loses verification", async () => {
  const { store, report } = setup();
  await seedRoute(store, "r1", { verification: "verified" });
  for (let i = 1; i <= 4; i++) {
    const result = await report(rider(`rider-${i}`), { routeId: "r1", type: "not_operating" });
    assertEquals(result.outdated, false);
  }
  const fifth = await report(rider("rider-5"), { routeId: "r1", type: "not_operating" });
  assertEquals(fifth.outdated, true);
  assertEquals((await store.getOutdated("r1"))?.types, ["not_operating"]);
  assertEquals((await store.get("r1"))?.verification, "unverified");
  // Still live: riders don't lose the route.
  assertEquals((await store.get("r1"))?.status, "published");
  assert(store.decisions.some((d) => d.decision === "auto_unverified"));
  assertEquals(store.decisions.filter((d) => d.decision === "outdated").length, 1);
});

Deno.test("a GTFS route can be possibly outdated too", async () => {
  const { store, report } = setup();
  store.gtfsNames.set("ROUTE_1", "Monumento - Navotas");
  for (let i = 1; i <= 5; i++) {
    await report(rider(`rider-${i}`), { routeId: "gtfs:ROUTE_1", type: "not_operating" });
  }
  assertEquals((await store.getOutdated("gtfs:ROUTE_1"))?.riders, 5);
});

Deno.test("the label goes once the reports behind it are gone", async () => {
  const { store } = setup();
  await seedRoute(store);
  await store.setOutdated("r1", ["wrong_stop"], 5);
  // All five reports are older than 30 days now.
  for (let i = 1; i <= 5; i++) {
    store.issues.push({
      id: i,
      route_key: "r1",
      reporter_id: `rider-${i}`,
      type: "wrong_stop",
      fare_paid: null,
      step_index: null,
      note: null,
      correction_id: null,
      status: "open",
      created_at: daysAgo(31),
    });
  }
  await reviewReports(store, "r1");
  assertEquals(await store.getOutdated("r1"), null);
});

// Fare agreement

Deno.test("three riders paying the same fare change it", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  await report(rider("a"), { routeId: "r1", type: "wrong_fare", farePaid: 15 });
  await report(rider("b"), { routeId: "r1", type: "wrong_fare", farePaid: 15.5 });
  const third = await report(rider("c"), { routeId: "r1", type: "wrong_fare", farePaid: 15 });
  assertEquals(third.fareChanged, true);
  const row = await store.get("r1");
  const steps = row!.data.steps as Record<string, unknown>[];
  assertEquals(steps[0].actualFare, 15);
  assertEquals(row!.data.price, "PHP 15");
  // The three reports are answered.
  assertEquals(store.issues.filter((i) => i.status === "resolved").length, 3);
  assert(store.decisions.some((d) => d.decision === "fare_updated" && d.actor === "system"));
});

Deno.test("a fare outside the usual range isn't changed", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  for (const uid of ["a", "b", "c"]) {
    await report(rider(uid), { routeId: "r1", type: "wrong_fare", farePaid: 40 });
  }
  const steps = (await store.get("r1"))!.data.steps as Record<string, unknown>[];
  assertEquals(steps[0].actualFare, 13);
  assertEquals(store.issues.filter((i) => i.status === "open").length, 3);
});

Deno.test("a tricycle fare isn't changed by reports", async () => {
  const { store, report } = setup();
  await seedRoute(store, "r1", {
    data: routeData({ steps: [{ mode: "Tricycle", actualFare: 20 }] }),
  });
  for (const uid of ["a", "b", "c"]) {
    await report(rider(uid), { routeId: "r1", type: "wrong_fare", farePaid: 25 });
  }
  const steps = (await store.get("r1"))!.data.steps as Record<string, unknown>[];
  assertEquals(steps[0].actualFare, 20);
});

Deno.test("if the fare rules can't be read, the fare stays", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  store.rules = new Error("down");
  for (const uid of ["a", "b", "c"]) {
    await report(rider(uid), { routeId: "r1", type: "wrong_fare", farePaid: 15 });
  }
  const steps = (await store.get("r1"))!.data.steps as Record<string, unknown>[];
  assertEquals(steps[0].actualFare, 13);
});

// Verification

async function confirmedRoute(store: MemoryStore) {
  await seedRoute(store, "r1", {
    feedback_summary: { fareAccurateYes: 3, scheduleAccurateYes: 3, stillOperatingYes: 3 },
  });
  store.operating.set("r1", 3);
}

Deno.test("rider confirmations verify a trusted route", async () => {
  const { store } = setup();
  await confirmedRoute(store);
  const { refreshVerification } = await import("./actions/reports.ts");
  assertEquals(await refreshVerification(store, "r1"), true);
  assertEquals((await store.get("r1"))?.verification, "verified");
  assert(store.decisions.some((d) => d.decision === "auto_verified"));
});

Deno.test("an open report stops riders verifying it", async () => {
  const { store, report } = setup();
  await confirmedRoute(store);
  await report(rider(), { routeId: "r1", type: "wrong_stop" });
  assertEquals((await store.get("r1"))?.verification, "unverified");
});

Deno.test("after a moderator unverifies, riders can't verify it again", async () => {
  const { store } = setup();
  await confirmedRoute(store);
  await store.update("r1", { verification: "verified" });
  await lifecycle.decide(moderator, { routeId: "r1", decision: "unverify", note: "Wrong terminal" }, store);
  const { refreshVerification } = await import("./actions/reports.ts");
  assertEquals(await refreshVerification(store, "r1"), false);
  assertEquals((await store.get("r1"))?.verification, "unverified");
});

Deno.test("a failed lookup never verifies", async () => {
  const { store } = setup();
  await confirmedRoute(store);
  store.issuesError = new Error("down");
  const { refreshVerification } = await import("./actions/reports.ts");
  assertEquals(await refreshVerification(store, "r1"), false);
  assertEquals((await store.get("r1"))?.verification, "unverified");
});

// Moderators

Deno.test("issue_queue: staff only, outdated routes first", async () => {
  const { store, report } = setup();
  await seedRoute(store, "quiet");
  await seedRoute(store, "loud");
  await report(rider("a"), { routeId: "quiet", type: "wrong_stop" });
  await report(rider("b"), { routeId: "quiet", type: "wrong_stop" });
  for (let i = 1; i <= 5; i++) {
    await report(rider(`rider-${i}`), { routeId: "loud", type: "not_operating" });
  }
  await assertHttp(() => reports.issue_queue(rider(), {}, store), 403, "forbidden");
  const queue = await reports.issue_queue(moderator, {}, store) as {
    routeKey: string;
    title: string;
    outdated: unknown;
    counts: Record<string, number>;
    issues: Issue[];
  }[];
  assertEquals(queue.map((q) => q.routeKey), ["loud", "quiet"]);
  assertEquals(queue[0].title, "Monumento to Malabon");
  assert(queue[0].outdated);
  assertEquals(queue[1].counts, { wrong_stop: 2 });
});

Deno.test("settle_issues: clears the reports and the label, and can verify again", async () => {
  const { store, report } = setup();
  await confirmedRoute(store);
  for (let i = 1; i <= 5; i++) {
    await report(rider(`rider-${i}`), { routeId: "r1", type: "not_operating" });
  }
  await assertHttp(
    () => reports.settle_issues(rider(), { routeId: "r1", resolution: "resolved" }, store),
    403,
    "forbidden",
  );
  await assertHttp(
    () => reports.settle_issues(moderator, { routeId: "r1", resolution: "maybe" }, store),
    400,
    "invalid",
  );
  const result = await reports.settle_issues(
    moderator,
    { routeId: "r1", resolution: "dismissed", note: "Checked, it still runs" },
    store,
  ) as { settled: number };
  assertEquals(result.settled, 5);
  assertEquals(await store.getOutdated("r1"), null);
  assertEquals(store.issues.every((i) => i.status === "dismissed"), true);
  assertEquals((await store.get("r1"))?.verification, "verified");
});

Deno.test("approving a path correction answers the wrong path reports", async () => {
  const { store, report } = setup();
  await seedRoute(store);
  for (let i = 1; i <= 5; i++) {
    await report(rider(`rider-${i}`), { routeId: "r1", type: "wrong_path" });
  }
  assert(await store.getOutdated("r1"));
  await seedRoute(store, "fix", {
    status: "pending",
    contributor_id: "rider-1",
    correction_of: "r1",
    data: routeData({ pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.661, lng: 120.991 }] }),
  });
  await lifecycle.decide(moderator, { routeId: "fix", decision: "approve", note: "Matches the ride" }, store);
  assertEquals(await store.getOutdated("r1"), null);
  assertEquals(store.issues.filter((i) => i.status === "resolved").length, 5);
});
