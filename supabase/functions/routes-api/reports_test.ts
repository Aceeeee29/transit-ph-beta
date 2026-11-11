import { assertEquals } from "jsr:@std/assert@^1.0.0";
import {
  fareAgreement,
  type Issue,
  isActive,
  outdatedTypes,
  rideIndexes,
  shouldVerify,
  trustScore,
  type VerifyFacts,
  withFare,
} from "./reports.ts";

const NOW = new Date("2026-11-10T12:00:00Z");
const daysAgo = (days: number) => new Date(NOW.getTime() - days * 86400000).toISOString();

let nextId = 1;
const issue = (extra: Partial<Issue> = {}): Issue => ({
  id: nextId++,
  route_key: "r1",
  reporter_id: "rider-1",
  type: "not_operating",
  fare_paid: null,
  step_index: null,
  note: null,
  correction_id: null,
  status: "open",
  created_at: daysAgo(1),
  ...extra,
});

const riders = (count: number, extra: Partial<Issue> = {}) =>
  Array.from({ length: count }, (_, i) => issue({ reporter_id: `rider-${i + 1}`, ...extra }));

// isActive

Deno.test("isActive: open and under 30 days", () => {
  assertEquals(isActive(issue({ created_at: daysAgo(29) }), NOW), true);
  assertEquals(isActive(issue({ created_at: daysAgo(31) }), NOW), false);
  assertEquals(isActive(issue({ status: "resolved" }), NOW), false);
  assertEquals(isActive(issue({ status: "dismissed" }), NOW), false);
  assertEquals(isActive(issue({ created_at: "not a date" }), NOW), false);
});

// outdatedTypes

Deno.test("outdatedTypes: 5 different riders with the same type", () => {
  assertEquals(outdatedTypes(riders(5), NOW), { types: ["not_operating"], riders: 5 });
});

Deno.test("outdatedTypes: 4 riders isn't enough", () => {
  assertEquals(outdatedTypes(riders(4), NOW), { types: [], riders: 0 });
});

Deno.test("outdatedTypes: one rider reporting many times counts once", () => {
  const same = Array.from({ length: 6 }, () => issue({ reporter_id: "rider-1" }));
  assertEquals(outdatedTypes(same, NOW).types, []);
});

Deno.test("outdatedTypes: different types don't add up", () => {
  const mixed = [
    ...riders(3, { type: "wrong_stop" }),
    ...riders(3, { type: "wrong_schedule" }),
  ];
  assertEquals(outdatedTypes(mixed, NOW).types, []);
});

Deno.test("outdatedTypes: old and settled reports don't count", () => {
  const list = [
    ...riders(3),
    issue({ reporter_id: "old", created_at: daysAgo(40) }),
    issue({ reporter_id: "done", status: "resolved" }),
  ];
  assertEquals(outdatedTypes(list, NOW).types, []);
});

Deno.test("outdatedTypes: lists every type over the limit, with the biggest count", () => {
  const list = [...riders(5, { type: "wrong_path" }), ...riders(6, { type: "wrong_fare", fare_paid: 20, step_index: 0 })];
  assertEquals(outdatedTypes(list, NOW), { types: ["wrong_fare", "wrong_path"], riders: 6 });
});

// fareAgreement

const fare = (reporter: string, paid: number, extra: Partial<Issue> = {}) =>
  issue({ reporter_id: reporter, type: "wrong_fare", fare_paid: paid, step_index: 0, ...extra });

Deno.test("fareAgreement: 3 riders within ₱1 agree, on the middle fare", () => {
  const result = fareAgreement([fare("a", 18), fare("b", 19), fare("c", 18.5)], NOW);
  assertEquals(result?.fare, 19);
  assertEquals(result?.riders, 3);
  assertEquals(result?.stepIndex, 0);
});

Deno.test("fareAgreement: 2 riders aren't enough", () => {
  assertEquals(fareAgreement([fare("a", 18), fare("b", 18)], NOW), null);
});

Deno.test("fareAgreement: fares more than ₱1 apart don't agree", () => {
  assertEquals(fareAgreement([fare("a", 18), fare("b", 19.5), fare("c", 21)], NOW), null);
});

Deno.test("fareAgreement: one rider can't be counted three times", () => {
  assertEquals(fareAgreement([fare("a", 18), fare("a", 18), fare("a", 18)], NOW), null);
});

Deno.test("fareAgreement: a rider's latest fare is the one that counts", () => {
  const result = fareAgreement([
    fare("a", 30, { created_at: daysAgo(5) }),
    fare("a", 18, { created_at: daysAgo(1) }),
    fare("b", 18),
    fare("c", 18),
  ], NOW);
  assertEquals(result?.fare, 18);
  assertEquals(result?.riders, 3);
});

Deno.test("fareAgreement: steps are counted apart", () => {
  const list = [fare("a", 18), fare("b", 18, { step_index: 1 }), fare("c", 18, { step_index: 2 })];
  assertEquals(fareAgreement(list, NOW), null);
});

Deno.test("fareAgreement: picks the bigger group", () => {
  const list = [
    fare("a", 15), fare("b", 15), fare("c", 15),
    fare("d", 25), fare("e", 25), fare("f", 25), fare("g", 25),
  ];
  assertEquals(fareAgreement(list, NOW)?.fare, 25);
});

Deno.test("fareAgreement: skips reports with no fare, no step or that aren't open", () => {
  const list = [
    fare("a", 18),
    fare("b", 18),
    issue({ reporter_id: "c", type: "wrong_fare", fare_paid: null, step_index: 0 }),
    issue({ reporter_id: "d", type: "wrong_fare", fare_paid: 18, step_index: null }),
    fare("e", 18, { status: "dismissed" }),
    fare("f", 18, { created_at: daysAgo(45) }),
  ];
  assertEquals(fareAgreement(list, NOW), null);
});

// withFare

Deno.test("withFare: changes the step and redoes the total when every ride has a fare", () => {
  const data = {
    price: "PHP 30",
    steps: [
      { mode: "Walk" },
      { mode: "Jeepney", actualFare: 13 },
      { mode: "Bus", actualFare: 17 },
    ],
  };
  const updated = withFare(data, 1, 15);
  assertEquals((updated.steps as Record<string, unknown>[])[1].actualFare, 15);
  assertEquals(updated.price, "PHP 32");
  // The original is left alone.
  assertEquals(data.steps[1].actualFare, 13);
});

Deno.test("withFare: moves the total by the difference when other rides were estimated", () => {
  const data = { price: "PHP 40", steps: [{ mode: "Jeepney", actualFare: 13 }, { mode: "Bus" }] };
  assertEquals(withFare(data, 0, 16).price, "PHP 43");
});

Deno.test("withFare: leaves a total it can't work out", () => {
  const data = { price: "PHP 40", steps: [{ mode: "Jeepney" }, { mode: "Bus" }] };
  assertEquals(withFare(data, 0, 16).price, "PHP 40");
  assertEquals(withFare({ price: "about 40", steps: [{ mode: "Jeepney", actualFare: 13 }, { mode: "Bus" }] }, 0, 16).price, "about 40");
});

Deno.test("rideIndexes: skips walks and copes with no steps", () => {
  assertEquals(rideIndexes({ steps: [{ mode: "Walk" }, { mode: "Jeepney" }, { mode: "walk" }, { mode: "Bus" }] }), [1, 3]);
  assertEquals(rideIndexes({}), []);
  assertEquals(rideIndexes({ steps: [null, { mode: 5 }] }), []);
});

// trustScore. The same cases are in test/route_trust_service_test.dart, so the
// app and the server can't drift apart.

const scored = (summary: Record<string, unknown>, updatedDaysAgo: number | null, status = "published") => ({
  status,
  feedback_summary: summary,
  updated_at: updatedDaysAgo === null ? null : daysAgo(updatedDaysAgo),
  created_at: null,
});

Deno.test("trustScore: three riders agreeing on everything, recently", () => {
  const summary = { fareAccurateYes: 3, scheduleAccurateYes: 3, stillOperatingYes: 3 };
  assertEquals(trustScore(scored(summary, 1), NOW), 74);
});

Deno.test("trustScore: mixed answers, a month and a half old", () => {
  const summary = { fareAccurateYes: 1, fareAccurateNo: 1, stillOperatingYes: 2, stillOperatingNo: 3 };
  assertEquals(trustScore(scored(summary, 40, "pending"), NOW), 21);
});

Deno.test("trustScore: rounds halves away from zero, like Dart", () => {
  // 3 yes, 5 no on the fare: -2/8 of 22 is -5.5, which Dart rounds to -6.
  assertEquals(trustScore(scored({ fareAccurateYes: 3, fareAccurateNo: 5 }, null), NOW), 14);
});

Deno.test("trustScore: copes with odd counters and stays between 0 and 100", () => {
  assertEquals(trustScore(scored({ fareAccurateYes: "3.0", stillOperatingNo: "x" }, 1), NOW), 48);
  assertEquals(trustScore(scored({ fareAccurateNo: 50, scheduleAccurateNo: 50, stillOperatingNo: 50 }, null, "rejected"), NOW), 0);
  const full = { fareAccurateYes: 9, scheduleAccurateYes: 9, stillOperatingYes: 9 };
  assertEquals(trustScore(scored(full, 0), NOW), 100);
});

// shouldVerify

const verifyFacts = (extra: Partial<VerifyFacts> = {}): VerifyFacts => ({
  row: {
    ...scored({ fareAccurateYes: 3, scheduleAccurateYes: 3, stillOperatingYes: 3 }, 1),
    verification: "unverified",
  },
  operatingRiders: 3,
  activeIssues: 0,
  outdated: false,
  unverifiedByStaff: false,
  ...extra,
});

Deno.test("shouldVerify: trusted, confirmed and no open problems", () => {
  assertEquals(shouldVerify(verifyFacts(), NOW), true);
});

Deno.test("shouldVerify: each missing condition stops it", () => {
  assertEquals(shouldVerify(verifyFacts({ operatingRiders: 2 }), NOW), false, "riders");
  assertEquals(shouldVerify(verifyFacts({ activeIssues: 1 }), NOW), false, "reports");
  assertEquals(shouldVerify(verifyFacts({ outdated: true }), NOW), false, "outdated");
  assertEquals(shouldVerify(verifyFacts({ unverifiedByStaff: true }), NOW), false, "staff");
  const low = verifyFacts();
  low.row = { ...low.row, feedback_summary: { stillOperatingYes: 3 } };
  assertEquals(shouldVerify(low, NOW), false, "trust");
  const verified = verifyFacts();
  verified.row = { ...verified.row, verification: "verified" };
  assertEquals(shouldVerify(verified, NOW), false, "already verified");
  const pending = verifyFacts();
  pending.row = { ...pending.row, status: "pending" };
  assertEquals(shouldVerify(pending, NOW), false, "not live");
});
