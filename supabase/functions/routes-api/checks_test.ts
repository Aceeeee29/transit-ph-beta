import { assertEquals, assertStringIncludes } from "jsr:@std/assert@^1.0.0";
import {
  type CheckContext,
  type CheckResult,
  isFareOnlyChange,
  outcomeOf,
  type RouteFacts,
  runChecks,
} from "./checks.ts";

// About 1 km along a road in Caloocan, in 3 short pieces.
const PATH = [
  { lat: 14.6500, lng: 120.9800 },
  { lat: 14.6525, lng: 120.9800 },
  { lat: 14.6550, lng: 120.9800 },
  { lat: 14.6575, lng: 120.9800 },
];

const route = (extra: Record<string, unknown> = {}) => ({
  id: "r1",
  startLocation: "Monumento",
  endLocation: "Malabon",
  steps: [{ mode: "Jeepney", instruction: "Ride", actualFare: 14 }],
  stepBoundaries: [3],
  pathPoints: PATH,
  ...extra,
});

const FACTS: RouteFacts = {
  target_exists: null,
  target_status: null,
  length_km: 1,
  camanava_km: 5,
  published_overlap: null,
  gtfs_overlap: null,
  repeat: null,
  correction_kept: null,
};

const OLD_ENOUGH = new Date(Date.now() - 30 * 86400000).toISOString();

const context = (extra: Partial<CheckContext> = {}): CheckContext => ({
  facts: FACTS,
  fareRules: {
    jeepney: { base: 14, base_km: 4, per_km: 1.94, source: "TransitPH estimate" },
    bus: { base: 18, base_km: 5, per_km: 2.22, source: "TransitPH estimate" },
    bus_aircon: { base: 18, base_km: 5, per_km: 3.18, source: "TransitPH estimate" },
    fx_van: { base: 40, base_km: 5, per_km: 4.57, source: "TransitPH estimate" },
    tricycle: { base: 16, base_km: 2, per_km: 5.33, source: "TransitPH estimate" },
  },
  accountCreatedAt: OLD_ENOUGH,
  publishedCount: 2,
  ...extra,
});

function check(results: CheckResult[], code: string): CheckResult {
  const found = results.find((r) => r.code === code);
  if (!found) throw new Error(`No check named ${code}`);
  return found;
}

const run = (r = route(), c = context()) => runChecks(r, c);
const resultOf = (code: string, r = route(), c = context()) => check(run(r, c), code).result;

Deno.test("a good route from a known contributor passes everything that applies", () => {
  const results = run();
  assertEquals(results.filter((r) => r.result === "fail" || r.result === "flag"), []);
  assertEquals(outcomeOf(results), "published");
});

Deno.test("every check has a message people can read", () => {
  for (const result of run()) {
    assertEquals(result.message.trim().length > 0, true, result.code);
  }
});

// H_REQUIRED

Deno.test("H_REQUIRED: each missing part fails", () => {
  const bad = [
    route({ startLocation: " " }),
    route({ endLocation: undefined }),
    route({ steps: [] }),
    route({ steps: "junk" }),
    route({ steps: [{ instruction: "no mode" }] }),
    route({ steps: [{ mode: "  " }] }),
    route({ pathPoints: [] }),
    route({ pathPoints: [PATH[0]] }),
    route({ pathPoints: "junk" }),
  ];
  for (const r of bad) assertEquals(resultOf("H_REQUIRED", r), "fail", JSON.stringify(r));
});

Deno.test("H_REQUIRED: the message says what's missing", () => {
  assertStringIncludes(check(run(route({ steps: [] })), "H_REQUIRED").message, "step");
});

Deno.test("a route with nothing in it doesn't crash any check", () => {
  const results = run({ id: "x" } as ReturnType<typeof route>);
  assertEquals(outcomeOf(results), "rejected");
});

// H_COORDS

Deno.test("H_COORDS: points outside the Philippines fail", () => {
  const tokyo = { lat: 35.68, lng: 139.69 };
  assertEquals(resultOf("H_COORDS", route({ pathPoints: [PATH[0], tokyo] })), "fail");
  assertEquals(resultOf("H_COORDS", route({ pathPoints: [{ lat: 0, lng: 0 }, PATH[0]] })), "fail");
  assertEquals(resultOf("H_COORDS", route({ startLat: 0, startLng: 0 })), "fail");
});

Deno.test("H_COORDS: anywhere in the Philippines passes, even outside CAMANAVA", () => {
  const cebu = [{ lat: 10.31, lng: 123.89 }, { lat: 10.32, lng: 123.90 }];
  assertEquals(resultOf("H_COORDS", route({ pathPoints: cebu })), "pass");
});

// H_TARGET

Deno.test("H_TARGET: not a correction is skipped", () => {
  assertEquals(resultOf("H_TARGET"), "skip");
});

Deno.test("H_TARGET: the target must exist and be published", () => {
  const correction = route({ correctionOf: "t1" });
  const facts = (target_exists: boolean, target_status: string | null) =>
    context({ facts: { ...FACTS, target_exists, target_status } });
  assertEquals(resultOf("H_TARGET", correction, facts(true, "published")), "pass");
  assertEquals(resultOf("H_TARGET", correction, facts(true, "pending")), "fail");
  assertEquals(resultOf("H_TARGET", correction, facts(false, null)), "fail");
});

Deno.test("H_TARGET: a real GTFS route counts", () => {
  const correction = route({ correctionOf: "gtfs:LTFRB_1" });
  const facts = context({ facts: { ...FACTS, target_exists: true, target_status: "published" } });
  assertEquals(resultOf("H_TARGET", correction, facts), "pass");
});

// H_REPEAT

Deno.test("H_REPEAT: 90% the same as your own recent route fails", () => {
  const repeat = (fraction: number) => context({ facts: { ...FACTS, repeat: { id: "old", fraction, status: "rejected" } } });
  assertEquals(resultOf("H_REPEAT", route(), repeat(0.9)), "fail");
  assertEquals(resultOf("H_REPEAT", route(), repeat(0.89)), "pass");
  assertEquals(resultOf("H_REPEAT", route(), context()), "pass");
});

Deno.test("H_REPEAT: both lines must cover each other", () => {
  const repeat = (fraction: number, other_fraction: number) =>
    context({ facts: { ...FACTS, repeat: { id: "old", fraction, other_fraction, status: "pending" } } });
  assertEquals(resultOf("H_REPEAT", route(), repeat(0.95, 0.9)), "fail");
  // A 1 km fix drawn along part of your own 5 km route, as seen on staging.
  assertEquals(resultOf("H_REPEAT", route(), repeat(1, 0.2)), "pass");
  assertEquals(resultOf("H_REPEAT", route(), repeat(0.95, 0.89)), "pass");
  const { detail } = check(run(route(), repeat(0.95, 0.92)), "H_REPEAT");
  assertEquals(detail.otherFraction, 0.92);
});

// H_FARE_IMPOSSIBLE

Deno.test("H_FARE_IMPOSSIBLE: zero or negative fares fail", () => {
  for (const actualFare of [0, -5]) {
    assertEquals(resultOf("H_FARE_IMPOSSIBLE", route({ steps: [{ mode: "Jeepney", actualFare }] })), "fail");
  }
});

Deno.test("H_FARE_IMPOSSIBLE: 5 times the fare table fails, just under doesn't", () => {
  const jeep = (actualFare: number) => route({ steps: [{ mode: "Jeepney", actualFare }] });
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", jeep(70)), "fail");
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", jeep(69)), "pass");
});

Deno.test("H_FARE_IMPOSSIBLE: covers every mode with a fare table", () => {
  const trike = (actualFare: number) => route({ steps: [{ mode: "Tricycle", actualFare }] });
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", trike(80)), "fail");
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", trike(50)), "pass");
});

Deno.test("H_FARE_IMPOSSIBLE: no fare entered and walking are fine", () => {
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", route({ steps: [{ mode: "Jeepney" }] })), "pass");
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", route({ steps: [{ mode: "Walk", actualFare: 0 }] })), "pass");
});

Deno.test("H_FARE_IMPOSSIBLE: a mode with no fare table only needs a positive fare", () => {
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", route({ steps: [{ mode: "Train", actualFare: 500 }] })), "pass");
  assertEquals(resultOf("H_FARE_IMPOSSIBLE", route({ steps: [{ mode: "Boat", actualFare: 0 }] })), "fail");
});

// S_FARE_RANGE

Deno.test("S_FARE_RANGE: within ±₱2 of a short jeepney fare passes", () => {
  const jeep = (actualFare: number) => route({ steps: [{ mode: "Jeepney", actualFare }] });
  assertEquals(resultOf("S_FARE_RANGE", jeep(14)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(12)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(16)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(11)), "flag");
  assertEquals(resultOf("S_FARE_RANGE", jeep(17)), "flag");
});

Deno.test("S_FARE_RANGE: a long trip uses 10% when that's more than ₱2", () => {
  // 11 km on a jeepney: 14 + 7 × 1.94 = 27.58, so ±2.76.
  const far = [{ lat: 14.65, lng: 120.98 }, { lat: 14.749, lng: 120.98 }];
  const jeep = (actualFare: number) =>
    route({ pathPoints: far, stepBoundaries: [1], steps: [{ mode: "Jeepney", actualFare }] });
  assertEquals(resultOf("S_FARE_RANGE", jeep(30)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(25)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(31)), "flag");
});

Deno.test("S_FARE_RANGE: a bus can be ordinary or aircon", () => {
  // 11 km: ordinary 31.32, aircon 37.08.
  const far = [{ lat: 14.65, lng: 120.98 }, { lat: 14.749, lng: 120.98 }];
  const bus = (actualFare: number) =>
    route({ pathPoints: far, stepBoundaries: [1], steps: [{ mode: "Bus", actualFare }] });
  assertEquals(resultOf("S_FARE_RANGE", bus(30)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", bus(40)), "pass");
  assertEquals(resultOf("S_FARE_RANGE", bus(44)), "flag");
});

Deno.test("S_FARE_RANGE: a jeepney can be traditional or modern", () => {
  // 11 km: traditional 27.58. With a modern rate of 15 + 7 × 2.2 = 30.4.
  const far = [{ lat: 14.65, lng: 120.98 }, { lat: 14.749, lng: 120.98 }];
  const jeep = (actualFare: number) =>
    route({ pathPoints: far, stepBoundaries: [1], steps: [{ mode: "Jeepney", actualFare }] });
  const rules = context().fareRules!;
  const withModern = context({
    fareRules: { ...rules, jeepney_modern: { base: 15, base_km: 4, per_km: 2.2, source: "TransitPH estimate" } },
  });
  assertEquals(resultOf("S_FARE_RANGE", jeep(33), withModern), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(25), withModern), "pass");
  assertEquals(resultOf("S_FARE_RANGE", jeep(34), withModern), "flag");
  // Without a modern rate, only the traditional fare counts.
  assertEquals(resultOf("S_FARE_RANGE", jeep(33)), "flag");
});

Deno.test("S_FARE_RANGE: each step uses its own length", () => {
  const twoSteps = route({
    pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.749, lng: 120.98 }, { lat: 14.75, lng: 120.98 }],
    stepBoundaries: [1, 2],
    steps: [{ mode: "Jeepney", actualFare: 28 }, { mode: "Jeepney", actualFare: 14 }],
  });
  assertEquals(resultOf("S_FARE_RANGE", twoSteps), "pass");
});

Deno.test("S_FARE_RANGE: no official fare for tricycles or FX", () => {
  for (const mode of ["Tricycle", "FX/Van", "Train"]) {
    assertEquals(resultOf("S_FARE_RANGE", route({ steps: [{ mode, actualFare: 500 }] })), "skip", mode);
  }
});

Deno.test("S_FARE_RANGE: the message shows the numbers and says it's an estimate", () => {
  const { message, detail } = check(run(route({ steps: [{ mode: "Jeepney", actualFare: 30 }] })), "S_FARE_RANGE");
  assertStringIncludes(message, "30");
  assertStringIncludes(message, "estimate");
  assertEquals(detail.fare, 30);
});

Deno.test("S_FARE_RANGE: real LTFRB rates are named as LTFRB", () => {
  const rules = context().fareRules!;
  const ltfrb = context({ fareRules: { ...rules, jeepney: { ...rules.jeepney, source: "LTFRB MC 2023-051" } } });
  const { message } = check(run(route({ steps: [{ mode: "Jeepney", actualFare: 30 }] }), ltfrb), "S_FARE_RANGE");
  assertStringIncludes(message, "LTFRB");
});

Deno.test("S_FARE_RANGE: a source that already says LTFRB isn't doubled", () => {
  const rules = context().fareRules!;
  const ltfrb = context({ fareRules: { ...rules, jeepney: { ...rules.jeepney, source: "LTFRB (effective 2026-09-28)" } } });
  const { message } = check(run(route({ steps: [{ mode: "Jeepney", actualFare: 30 }] }), ltfrb), "S_FARE_RANGE");
  assertStringIncludes(message, "(LTFRB (effective 2026-09-28))");
  assertEquals(message.includes("LTFRB (LTFRB"), false);
});

// S_AREA

Deno.test("S_AREA: 3 km inside CAMANAVA passes, however long the route is", () => {
  const area = (camanava_km: number, length_km: number) => context({ facts: { ...FACTS, camanava_km, length_km } });
  assertEquals(resultOf("S_AREA", route(), area(3, 40)), "pass");
  assertEquals(resultOf("S_AREA", route(), area(2.99, 40)), "flag");
  assertEquals(resultOf("S_AREA", route(), area(0, 10)), "flag");
});

Deno.test("S_AREA: half the route inside CAMANAVA passes too", () => {
  const area = (camanava_km: number, length_km: number) => context({ facts: { ...FACTS, camanava_km, length_km } });
  assertEquals(resultOf("S_AREA", route(), area(1, 2)), "pass");
  assertEquals(resultOf("S_AREA", route(), area(0.99, 2)), "flag");
  const { message } = check(run(route(), area(0.5, 2)), "S_AREA");
  assertStringIncludes(message, "25%");
  assertStringIncludes(message, "half the route");
});

Deno.test("S_AREA: no length means only the 3 km rule counts", () => {
  const facts = context({ facts: { ...FACTS, camanava_km: 2, length_km: null } });
  assertEquals(resultOf("S_AREA", route(), facts), "flag");
});

// S_OVERLAP

Deno.test("S_OVERLAP: 70% both ways matches a published route, and suggests a correction", () => {
  const overlap = (fraction: number, other_fraction = 0.9) =>
    context({ facts: { ...FACTS, published_overlap: { id: "p1", name: "A to B", source: "rider", fraction, other_fraction } } });
  assertEquals(resultOf("S_OVERLAP", route(), overlap(0.69)), "pass");
  assertEquals(resultOf("S_OVERLAP", route(), overlap(1, 0.69)), "pass");
  assertEquals(resultOf("S_OVERLAP", route(), overlap(0.7, 0.7)), "flag");
  const result = check(run(route(), overlap(0.7)), "S_OVERLAP");
  assertEquals(result.result, "flag");
  assertStringIncludes(result.message, "A to B");
  assertStringIncludes(result.message, "correction");
  assertEquals(result.detail.routeId, "p1");
});

Deno.test("S_OVERLAP: a short route along part of a long one isn't a match", () => {
  // All of the new line is on the other route, but it covers only 30% of it.
  const facts = context({ facts: { ...FACTS, published_overlap: { id: "p1", name: "A to B", source: "osm", fraction: 1, other_fraction: 0.3 } } });
  assertEquals(resultOf("S_OVERLAP", route(), facts), "pass");
});

Deno.test("S_OVERLAP: without the other side's number it flags, to be safe", () => {
  const facts = context({ facts: { ...FACTS, published_overlap: { id: "p1", name: "A to B", source: "rider", fraction: 0.8 } } });
  assertEquals(resultOf("S_OVERLAP", route(), facts), "flag");
});

Deno.test("S_OVERLAP: a GTFS route counts too, and says where it's from", () => {
  const facts = context({ facts: { ...FACTS, gtfs_overlap: { id: "L1", name: "Monumento-Malabon", source: "gtfs", fraction: 0.8, other_fraction: 0.75 } } });
  const result = check(run(route(), facts), "S_OVERLAP");
  assertEquals(result.result, "flag");
  assertStringIncludes(result.message, "DOTC 2013");
  assertEquals(result.detail.routeId, "gtfs:L1");
  assertEquals(result.detail.otherFraction, 0.75);
});

Deno.test("S_OVERLAP: a DOTC trip needs most of its stops on the new line", () => {
  const gtfs = (other_fraction: number) =>
    context({ facts: { ...FACTS, gtfs_overlap: { id: "L1", name: "Monumento-Malabon", source: "gtfs", fraction: 0.9, other_fraction } } });
  assertEquals(resultOf("S_OVERLAP", route(), gtfs(0.69)), "pass");
  assertEquals(resultOf("S_OVERLAP", route(), gtfs(0.7)), "flag");
});

Deno.test("S_OVERLAP: a correction is meant to overlap, so it's skipped", () => {
  const facts = context({ facts: { ...FACTS, target_exists: true, target_status: "published", published_overlap: { id: "p1", name: "A", source: "rider", fraction: 1 } } });
  assertEquals(resultOf("S_OVERLAP", route({ correctionOf: "t1" }), facts), "skip");
});

// S_CORRECTION_SIZE

Deno.test("S_CORRECTION_SIZE: changing more than 40% flags", () => {
  const correction = route({ correctionOf: "t1" });
  const kept = (correction_kept: number) =>
    context({ facts: { ...FACTS, target_exists: true, target_status: "published", correction_kept } });
  assertEquals(resultOf("S_CORRECTION_SIZE", correction, kept(0.6)), "pass");
  assertEquals(resultOf("S_CORRECTION_SIZE", correction, kept(0.59)), "flag");
});

Deno.test("S_CORRECTION_SIZE: nothing to compare is skipped", () => {
  assertEquals(resultOf("S_CORRECTION_SIZE"), "skip");
  const gtfs = context({ facts: { ...FACTS, target_exists: true, target_status: "published" } });
  assertEquals(resultOf("S_CORRECTION_SIZE", route({ correctionOf: "gtfs:L1" }), gtfs), "skip");
});

// S_DRAWN_GAPS

Deno.test("S_DRAWN_GAPS: a straight jump over 1 km flags", () => {
  // 0.0091 degrees of latitude is about 1,012 m. 0.0089 is about 990 m.
  const gap = (size: number) => route({ pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.65 + size, lng: 120.98 }] });
  assertEquals(resultOf("S_DRAWN_GAPS", gap(0.0091)), "flag");
  assertEquals(resultOf("S_DRAWN_GAPS", gap(0.0089)), "pass");
});

// S_NEW_CONTRIBUTOR

Deno.test("S_NEW_CONTRIBUTOR: needs 7 days and one published route", () => {
  const recent = new Date(Date.now() - 6 * 86400000).toISOString();
  assertEquals(resultOf("S_NEW_CONTRIBUTOR", route(), context({ accountCreatedAt: recent })), "flag");
  assertEquals(resultOf("S_NEW_CONTRIBUTOR", route(), context({ publishedCount: 0 })), "flag");
  assertEquals(resultOf("S_NEW_CONTRIBUTOR", route(), context({ accountCreatedAt: null })), "flag");
  assertEquals(resultOf("S_NEW_CONTRIBUTOR", route(), context()), "pass");
});

Deno.test("S_NEW_CONTRIBUTOR: skipped for staff, whose account isn't the contributor's", () => {
  assertEquals(resultOf("S_NEW_CONTRIBUTOR", route(), context({ accountCreatedAt: null, publishedCount: 0, byStaff: true })), "skip");
});

// When the map questions can't be answered

Deno.test("if the map checks fail to run, the route goes to a moderator, never live", () => {
  const results = run(route(), context({ facts: null }));
  assertEquals(check(results, "S_AREA").result, "flag");
  assertEquals(check(results, "S_OVERLAP").result, "flag");
  assertEquals(check(results, "H_REPEAT").result, "flag");
  assertEquals(outcomeOf(results), "pending");
});

Deno.test("if the fare table can't load, fares go to a moderator", () => {
  const results = run(route(), context({ fareRules: null }));
  assertEquals(check(results, "S_FARE_RANGE").result, "flag");
  assertEquals(check(results, "H_FARE_IMPOSSIBLE").result, "pass");
  assertEquals(outcomeOf(results), "pending");
});

Deno.test("an unanswered target can't be confirmed, so a moderator checks it", () => {
  const facts = context({ facts: { ...FACTS, target_exists: null } });
  assertEquals(resultOf("H_TARGET", route({ correctionOf: "gtfs:L1" }), facts), "flag");
});

// Outcomes

Deno.test("outcome: any fail rejects, even with flags", () => {
  const r = (result: CheckResult["result"]): CheckResult => ({ code: "X", result, message: "m", detail: {} });
  assertEquals(outcomeOf([r("pass"), r("flag"), r("fail")]), "rejected");
  assertEquals(outcomeOf([r("pass"), r("flag")]), "pending");
  assertEquals(outcomeOf([r("pass"), r("skip")]), "published");
});

// Fare-only corrections

const target = () => route({ id: "t1" });

Deno.test("isFareOnlyChange: only a jeepney or bus fare changing counts", () => {
  const correction = (actualFare: number, extra = {}) =>
    route({ id: "c1", correctionOf: "t1", steps: [{ mode: "Jeepney", instruction: "Ride", actualFare }], ...extra });
  assertEquals(isFareOnlyChange(correction(15), target()), true);
  assertEquals(isFareOnlyChange(correction(14), target()), false, "nothing changed");
  assertEquals(isFareOnlyChange(correction(15, { pathPoints: [PATH[0], PATH[1]] }), target()), false, "path changed");
});

Deno.test("isFareOnlyChange: another step field changing doesn't count", () => {
  const moved = route({ steps: [{ mode: "Jeepney", instruction: "Ride elsewhere", actualFare: 15 }] });
  assertEquals(isFareOnlyChange(moved, target()), false);
});

Deno.test("isFareOnlyChange: a tricycle fare isn't official, so it doesn't count", () => {
  const trike = (actualFare: number) => route({ steps: [{ mode: "Tricycle", instruction: "Ride", actualFare }] });
  assertEquals(isFareOnlyChange(trike(20), trike(30)), false);
});

Deno.test("isFareOnlyChange: key order doesn't matter", () => {
  const reordered = route({ steps: [{ actualFare: 15, instruction: "Ride", mode: "Jeepney" }] });
  assertEquals(isFareOnlyChange(reordered, target()), true);
});

Deno.test("isFareOnlyChange: a different number of steps doesn't count", () => {
  const more = route({ steps: [{ mode: "Jeepney", instruction: "Ride", actualFare: 15 }, { mode: "Walk" }] });
  assertEquals(isFareOnlyChange(more, target()), false);
});
