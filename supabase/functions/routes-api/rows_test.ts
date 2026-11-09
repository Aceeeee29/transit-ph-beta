import { assertEquals } from "jsr:@std/assert@^1.0.0";
import { rowFromRouteJson } from "./rows.ts";
import { MemoryStore } from "./store_memory.ts";
import type { NewRouteRow } from "./rows.ts";

const point = (lat: unknown, lng: unknown) => ({ lat, lng });

Deno.test("geom is built from the path, longitude first", () => {
  const row = rowFromRouteJson(
    {
      id: "r1",
      pathPoints: [point(14.65, 120.98), point(14.66, 120.99), point(14.67, 121)],
    },
    "uid-1",
  );
  assertEquals(row.geom, "SRID=4326;LINESTRING(120.98 14.65,120.99 14.66,121 14.67)");
});

Deno.test("one point can't make a line", () => {
  const row = rowFromRouteJson({ id: "r1", pathPoints: [point(14.65, 120.98)] }, "uid-1");
  assertEquals(row.geom, null);
});

Deno.test("old routes with no path don't crash", () => {
  assertEquals(rowFromRouteJson({ id: "r1" }, "uid-1").geom, null);
  assertEquals(rowFromRouteJson({ id: "r1", pathPoints: [] }, "uid-1").geom, null);
  assertEquals(rowFromRouteJson({ id: "r1", pathPoints: "junk" }, "uid-1").geom, null);
});

Deno.test("points that aren't real coordinates are left out of geom", () => {
  const row = rowFromRouteJson(
    {
      id: "r1",
      pathPoints: [
        point(14.65, 120.98),
        point("not a number", 120.98),
        point(95, 120.98), // no such latitude
        point(14.66, 200), // no such longitude
        null,
        point(14.67, 121),
      ],
    },
    "uid-1",
  );
  assertEquals(row.geom, "SRID=4326;LINESTRING(120.98 14.65,121 14.67)");
});

Deno.test("coordinates saved as text still count", () => {
  // The app's Route.fromJson accepts these, so old routes may have them.
  const row = rowFromRouteJson(
    {
      id: "r1",
      pathPoints: [point("14.65", "120.98"), point("14.66", "120.99")],
      startLat: "14.65",
      startLng: "120.98",
    },
    "uid-1",
  );
  assertEquals(row.geom, "SRID=4326;LINESTRING(120.98 14.65,120.99 14.66)");
  assertEquals(row.start_pt, "SRID=4326;POINT(120.98 14.65)");
});

Deno.test("start and end points are built, longitude first", () => {
  const row = rowFromRouteJson(
    { id: "r1", startLat: 14.65, startLng: 120.98, endLat: 14.7, endLng: 121 },
    "uid-1",
  );
  assertEquals(row.start_pt, "SRID=4326;POINT(120.98 14.65)");
  assertEquals(row.end_pt, "SRID=4326;POINT(121 14.7)");
});

Deno.test("missing start or end points stay null", () => {
  const row = rowFromRouteJson({ id: "r1", startLat: 14.65, endLng: null }, "uid-1");
  assertEquals(row.start_pt, null);
  assertEquals(row.end_pt, null);
});

Deno.test("source comes from the id", () => {
  assertEquals(rowFromRouteJson({ id: "osm-bus-1" }, null).source, "osm");
  assertEquals(rowFromRouteJson({ id: "abc123" }, "uid-1").source, "rider");
});

Deno.test("server-owned fields are taken out of data", () => {
  const { data } = rowFromRouteJson(
    {
      id: "r1",
      startLocation: "A",
      steps: [],
      views: 99,
      upvotes: 99,
      downvotes: 99,
      approvalStatus: "approved",
      createdAt: "x",
      updatedAt: "x",
      feedbackSummary: { fareAccurateYes: 99 },
      contributorId: "someone-else",
      contributorName: "Someone Else",
      contributorClosed: true,
      verification: "verified",
      revision: 9,
      latestDecision: { decision: "approved" },
    },
    "uid-1",
  );
  assertEquals(data, { id: "r1", startLocation: "A", steps: [] });
});

Deno.test("the app can't choose who owns a route or its status", () => {
  const row = rowFromRouteJson(
    {
      id: "r1",
      contributorId: "someone-else",
      status: "published",
      verification: "verified",
      approvalStatus: "approved",
    },
    "uid-1",
  ) as Record<string, unknown>;
  assertEquals(row.contributor_id, "uid-1");
  assertEquals("status" in row, false);
  assertEquals("verification" in row, false);
});

Deno.test("correctionOf is copied to correction_of", () => {
  const row = rowFromRouteJson({ id: "r1", correctionOf: "gtfs:ABC" }, "uid-1");
  assertEquals(row.correction_of, "gtfs:ABC");
  assertEquals(rowFromRouteJson({ id: "r2" }, "uid-1").correction_of, null);
});

const newRow = (id: string, contributor: string | null = "uid-1"): NewRouteRow => ({
  ...rowFromRouteJson({ id }, contributor),
  status: "pending",
});

Deno.test("store: a conditional update only applies at the expected status", async () => {
  // Two moderators can both load a pending route. Only the first decision wins.
  const store = new MemoryStore();
  await store.insert(newRow("r1"));
  const first = await store.update("r1", { status: "published" }, "pending");
  const second = await store.update("r1", { status: "rejected" }, "pending");
  assertEquals(first?.status, "published");
  assertEquals(second, null);
  assertEquals((await store.get("r1"))?.status, "published");
});

Deno.test("store: counting pending routes can skip one", async () => {
  const store = new MemoryStore();
  await store.insert(newRow("r1"));
  await store.insert(newRow("r2"));
  await store.insert(newRow("r3", "uid-2"));
  assertEquals(await store.countPending("uid-1"), 2);
  assertEquals(await store.countPending("uid-1", "r1"), 1);
});

Deno.test("store: latest decision per route", async () => {
  const store = new MemoryStore();
  const add = (route_id: string, decision: string) =>
    store.addDecision({ route_id, revision: 1, actor: "system", decision, reason_codes: [], note: null });
  await add("r1", "rejected");
  await add("r1", "approved");
  await add("r2", "rejected");
  const latest = await store.latestDecisions(["r1", "r2", "r3"]);
  assertEquals(latest.get("r1")?.decision, "approved");
  assertEquals(latest.get("r2")?.decision, "rejected");
  assertEquals(latest.has("r3"), false);
});

Deno.test("store: a row read back can't change what's stored", async () => {
  const store = new MemoryStore();
  await store.insert(newRow("r1"));
  const copy = await store.get("r1");
  copy!.data.changed = true;
  assertEquals((await store.get("r1"))?.data.changed, undefined);
});
