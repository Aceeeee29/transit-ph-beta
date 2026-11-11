// The automatic checklist. Every route that's submitted or resubmitted runs
// through these fixed rules. Each result is stored and shown word for word to
// the contributor and to moderators, so "why" always has an answer.
//
// fail: rejected right away. flag: goes to a moderator. All pass: goes live as
// Unverified. If a check can't get its answer, it flags instead of passing,
// because an unchecked route must never go live on its own.

export const RULE_VERSION = 2;

export type CheckResult = {
  code: string;
  result: "pass" | "fail" | "flag" | "skip";
  message: string;
  detail: Record<string, unknown>;
};

export type Outcome = "published" | "pending" | "rejected";

// fraction: how much of the new line runs along the other one.
// other_fraction: how much of the other one the new line covers. For a DOTC
// trip it's the share of the trip's stops the new line passes.
type Overlap = { id: string; name: string; source: string; fraction: number; other_fraction?: number | null };

// What route_geometry_facts answers. Null means it couldn't say.
export type RouteFacts = {
  target_exists: boolean | null;
  target_status: string | null;
  length_km: number | null;
  camanava_km: number | null;
  published_overlap: Overlap | null;
  gtfs_overlap: Overlap | null;
  repeat: { id: string; fraction: number; status: string; other_fraction?: number | null } | null;
  correction_kept: number | null;
};

export type FareRule = { base: number; base_km: number; per_km: number; source: string };
export type FareRules = Record<string, FareRule>;

export type CheckContext = {
  // Null when the database couldn't answer.
  facts: RouteFacts | null;
  fareRules: FareRules | null;
  accountCreatedAt: string | null;
  publishedCount: number;
  // True when staff send it. They're the ones who'd review it, and the account
  // above is theirs, not the contributor's.
  byStaff?: boolean;
};

type Route = Record<string, unknown>;
type Step = Record<string, unknown>;
type Point = { lat: number; lng: number };

const MIN_CAMANAVA_KM = 3;
const MIN_CAMANAVA_SHARE = 0.5;
const OVERLAP_LIMIT = 0.7;
const REPEAT_LIMIT = 0.9;
const CORRECTION_KEEP = 0.6;
const MAX_STRAIGHT_JUMP_M = 1000;
const MIN_ACCOUNT_DAYS = 7;
const IMPOSSIBLE_FARE_TIMES = 5;

// A box around the Philippines. Rough on purpose: it catches wrong coordinates,
// and the area check covers the rest.
const PH = { minLat: 4.5, maxLat: 21.5, minLng: 116, maxLng: 127 };

const isFilled = (value: unknown) => typeof value === "string" && value.trim() !== "";
const stepsOf = (route: Route): Step[] => (Array.isArray(route.steps) ? (route.steps as Step[]) : []);

function validPoints(route: Route): Point[] {
  if (!Array.isArray(route.pathPoints)) return [];
  return route.pathPoints.flatMap((p) => {
    const lat = Number(p?.lat);
    const lng = Number(p?.lng);
    return p?.lat != null && p?.lng != null && Number.isFinite(lat) && Number.isFinite(lng) ? [{ lat, lng }] : [];
  });
}

function metersBetween(a: Point, b: Point): number {
  const rad = (degrees: number) => (degrees * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

function lengthKm(points: Point[]): number {
  let meters = 0;
  for (let i = 1; i < points.length; i++) meters += metersBetween(points[i - 1], points[i]);
  return meters / 1000;
}

// Each step's own length, from where it ends on the line. Null when the route
// doesn't say where its steps end, unless there's only one step.
function stepLengthsKm(route: Route, points: Point[]): (number | null)[] {
  const steps = stepsOf(route);
  if (steps.length === 1) return [lengthKm(points)];
  const boundaries = Array.isArray(route.stepBoundaries) ? route.stepBoundaries as unknown[] : [];
  if (boundaries.length !== steps.length || !boundaries.every((b) => typeof b === "number")) {
    return steps.map(() => null);
  }
  let start = 0;
  return (boundaries as number[]).map((boundary) => {
    const end = Math.min(boundary, points.length - 1);
    const km = end > start ? lengthKm(points.slice(start, end + 1)) : 0;
    start = Math.max(start, end);
    return km;
  });
}

const fareFor = (rule: FareRule, km: number) => (km <= rule.base_km ? rule.base : rule.base + (km - rule.base_km) * rule.per_km);
const peso = (amount: number) => `₱${Math.round(amount * 100) / 100}`;
// "LTFRB (effective 2026-09-28)" is shown as it is. Older rows only had the
// circular number, so those get "LTFRB" in front.
const fareSource = (rule: FareRule) => {
  if (/estimate/i.test(rule.source)) return "TransitPH estimate";
  return /^LTFRB\b/i.test(rule.source.trim()) ? rule.source.trim() : `LTFRB (${rule.source})`;
};
const hasFare = (step: Step) => typeof step.actualFare === "number";

// The fares a step could fairly cost, low to high. Buses run both ordinary and
// aircon on the same road, so both count. Jeepneys are the same with
// traditional and modern ones. Null when the mode has no fare table.
function expectedFares(mode: string, km: number, rules: FareRules): { low: number; high: number; rule: FareRule } | null {
  const m = mode.toLowerCase();
  if (m === "jeepney" && rules.jeepney) {
    const low = fareFor(rules.jeepney, km);
    const high = rules.jeepney_modern ? Math.max(low, fareFor(rules.jeepney_modern, km)) : low;
    return { low, high, rule: rules.jeepney };
  }
  if (m === "bus" && rules.bus) {
    const low = fareFor(rules.bus, km);
    const high = rules.bus_aircon ? fareFor(rules.bus_aircon, km) : low;
    return { low, high, rule: rules.bus };
  }
  if (m === "fx/van" && rules.fx_van) {
    const fare = fareFor(rules.fx_van, km);
    return { low: fare, high: fare, rule: rules.fx_van };
  }
  if (m === "tricycle" && rules.tricycle) {
    const fare = fareFor(rules.tricycle, km);
    return { low: fare, high: fare, rule: rules.tricycle };
  }
  return null;
}

const isOfficialFareMode = (mode: unknown) => typeof mode === "string" && ["jeepney", "bus"].includes(mode.toLowerCase());

function pass(code: string, message: string, detail: Record<string, unknown> = {}): CheckResult {
  return { code, result: "pass", message, detail };
}
function fail(code: string, message: string, detail: Record<string, unknown> = {}): CheckResult {
  return { code, result: "fail", message, detail };
}
function flag(code: string, message: string, detail: Record<string, unknown> = {}): CheckResult {
  return { code, result: "flag", message, detail };
}
function skip(code: string, message: string): CheckResult {
  return { code, result: "skip", message, detail: {} };
}

// Used when the database can't answer a question.
const unanswered = (code: string, topic: string) =>
  flag(code, `Couldn't check ${topic} automatically, so a moderator needs to look.`, { unanswered: true });

function checkRequired(route: Route, points: Point[]): CheckResult {
  const missing: string[] = [];
  if (!isFilled(route.startLocation)) missing.push("a start name");
  if (!isFilled(route.endLocation)) missing.push("an end name");
  const steps = stepsOf(route);
  if (steps.length === 0) missing.push("at least one step");
  else if (!steps.every((s) => isFilled(s?.mode))) missing.push("a mode for every step");
  if (points.length < 2) missing.push("a line with at least 2 points");
  return missing.length > 0
    ? fail("H_REQUIRED", `This route is missing ${missing.join(", ")}.`, { missing })
    : pass("H_REQUIRED", "All the required details are there.");
}

function checkCoords(route: Route, points: Point[]): CheckResult {
  const candidates = [...points];
  if (route.startLat != null && route.startLng != null) {
    candidates.push({ lat: Number(route.startLat), lng: Number(route.startLng) });
  }
  if (route.endLat != null && route.endLng != null) {
    candidates.push({ lat: Number(route.endLat), lng: Number(route.endLng) });
  }
  const bad = candidates.filter(
    (p) => !(p.lat >= PH.minLat && p.lat <= PH.maxLat && p.lng >= PH.minLng && p.lng <= PH.maxLng),
  );
  return bad.length > 0
    ? fail("H_COORDS", "Part of this route is outside the Philippines. Check the points on the map.", { badPoints: bad.length })
    : pass("H_COORDS", "Every point is in the Philippines.");
}

function checkTarget(route: Route, facts: RouteFacts | null): CheckResult {
  const code = "H_TARGET";
  if (!isFilled(route.correctionOf)) return skip(code, "This isn't a correction.");
  if (!facts || facts.target_exists === null) return unanswered(code, "the route being corrected");
  if (!facts.target_exists) return fail(code, "The route you're correcting doesn't exist anymore.");
  if (facts.target_status !== "published") return fail(code, "The route you're correcting isn't live, so it can't be corrected yet.");
  return pass(code, "The route being corrected exists.");
}

function checkRepeat(facts: RouteFacts | null): CheckResult {
  const code = "H_REPEAT";
  if (!facts) return unanswered(code, "for repeat submissions");
  const repeat = facts.repeat;
  // Both lines must cover each other. A short correction along part of your
  // own longer route isn't a repeat. Without the other side's number, it
  // falls back to the one-way rule.
  const isRepeat = repeat !== null &&
    repeat.fraction >= REPEAT_LIMIT &&
    (repeat.other_fraction == null || repeat.other_fraction >= REPEAT_LIMIT);
  if (repeat && isRepeat) {
    const message = repeat.status === "rejected"
      ? "This is almost the same as a route of yours a moderator already rejected. Edit that route from your profile instead."
      : "This is almost the same as a route you sent in the last 7 days.";
    return fail(code, message, { routeId: repeat.id, fraction: repeat.fraction, otherFraction: repeat.other_fraction ?? null });
  }
  return pass(code, "This isn't a repeat of a route you sent recently.");
}

function checkFareImpossible(route: Route, points: Point[], rules: FareRules | null): CheckResult {
  const code = "H_FARE_IMPOSSIBLE";
  const lengths = stepLengthsKm(route, points);
  const wholeKm = lengthKm(points);
  const steps = stepsOf(route);
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    if (!hasFare(step) || !isFilled(step.mode) || String(step.mode).toLowerCase() === "walk") continue;
    const fare = step.actualFare as number;
    if (fare <= 0) {
      return fail(code, `Step ${i + 1} has a fare of ${peso(fare)}. A fare must be more than ₱0.`, { step: i + 1, fare });
    }
    // Without the table we can't judge the size. S_FARE_RANGE flags that.
    if (!rules) continue;
    // If the step's length is unknown, use the whole route, which is the kindest.
    const expected = expectedFares(String(step.mode), lengths[i] ?? wholeKm, rules);
    if (expected && fare >= expected.high * IMPOSSIBLE_FARE_TIMES) {
      return fail(
        code,
        `Step ${i + 1}'s fare of ${peso(fare)} is too high for this distance. Check the amount.`,
        { step: i + 1, fare, expected: Math.round(expected.high * 100) / 100 },
      );
    }
  }
  return pass(code, "The fares entered are possible.");
}

function checkFareRange(route: Route, points: Point[], rules: FareRules | null): CheckResult {
  const code = "S_FARE_RANGE";
  const steps = stepsOf(route);
  const official = steps.map((step, i) => ({ step, i })).filter(({ step }) => hasFare(step) && isOfficialFareMode(step.mode));
  if (official.length === 0) return skip(code, "No official fare to compare. Only jeepneys and buses have one.");
  if (!rules) return unanswered(code, "the fare");

  const lengths = stepLengthsKm(route, points);
  for (const { step, i } of official) {
    const km = lengths[i];
    if (km === null) return flag(code, "Couldn't tell how long each step is, so a moderator needs to check the fares.");
    const expected = expectedFares(String(step.mode), km, rules);
    if (!expected) return unanswered(code, "the fare");
    const tolerance = Math.max(2, expected.high * 0.1);
    const low = expected.low - Math.max(2, expected.low * 0.1);
    const high = expected.high + tolerance;
    const fare = step.actualFare as number;
    if (fare < low || fare > high) {
      return flag(
        code,
        `Step ${i + 1}'s fare of ${peso(fare)} is outside the usual ${peso(low)} to ${peso(high)} for ${km.toFixed(1)} km (${fareSource(expected.rule)}).`,
        { step: i + 1, fare, low: Math.round(low * 100) / 100, high: Math.round(high * 100) / 100, km: Math.round(km * 10) / 10 },
      );
    }
  }
  return pass(code, "The jeepney and bus fares are in the usual range.");
}

function checkArea(facts: RouteFacts | null): CheckResult {
  const code = "S_AREA";
  if (!facts || facts.camanava_km === null) return unanswered(code, "the service area");
  const km = facts.camanava_km;
  // A short route can be all in CAMANAVA and still be under 3 km, so half the
  // route counts too.
  const share = facts.length_km ? km / facts.length_km : null;
  const percent = share === null ? null : Math.round(Math.min(share, 1) * 100);
  const detail = { km, sharePercent: percent };
  if (km >= MIN_CAMANAVA_KM) return pass(code, `${km} km of this route is inside CAMANAVA.`, detail);
  if (share !== null && share >= MIN_CAMANAVA_SHARE) {
    return pass(code, `${percent}% of this route is inside CAMANAVA.`, detail);
  }
  const shareText = percent === null ? "" : ` (${percent}%)`;
  return flag(
    code,
    `Only ${km} km${shareText} of this route is inside CAMANAVA. It needs at least ${MIN_CAMANAVA_KM} km or half the route.`,
    detail,
  );
}

function checkOverlap(route: Route, facts: RouteFacts | null): CheckResult {
  const code = "S_OVERLAP";
  if (isFilled(route.correctionOf)) return skip(code, "A correction is meant to follow an existing route.");
  if (!facts) return unanswered(code, "for similar routes");
  const percent = (fraction: number) => `${Math.round(fraction * 100)}%`;
  // Only a true match counts: each line covers most of the other. A short route
  // along part of a long one is a different route. If the database didn't say
  // how much of the other line is covered, it flags, to be safe.
  const isMatch = (overlap: Overlap | null): overlap is Overlap =>
    overlap !== null &&
    overlap.fraction >= OVERLAP_LIMIT &&
    (overlap.other_fraction == null || overlap.other_fraction >= OVERLAP_LIMIT);
  const detailOf = (overlap: Overlap, routeId: string) => ({
    routeId,
    fraction: overlap.fraction,
    otherFraction: overlap.other_fraction ?? null,
  });
  const published = facts.published_overlap;
  if (isMatch(published)) {
    const from = published.source === "osm" ? "OpenStreetMap route" : "route";
    return flag(
      code,
      `This matches the ${from} "${published.name}": ${percent(published.fraction)} of it follows that route in the same direction. If it's the same route, send a correction of it instead.`,
      detailOf(published, published.id),
    );
  }
  const gtfs = facts.gtfs_overlap;
  if (isMatch(gtfs)) {
    return flag(
      code,
      `This matches "${gtfs.name}" from the DOTC 2013 data: ${percent(gtfs.fraction)} of it follows that route. If it's the same route, send a correction of it instead.`,
      detailOf(gtfs, `gtfs:${gtfs.id}`),
    );
  }
  return pass(code, "This doesn't repeat an existing route.");
}

function checkCorrectionSize(route: Route, facts: RouteFacts | null): CheckResult {
  const code = "S_CORRECTION_SIZE";
  if (!isFilled(route.correctionOf)) return skip(code, "This isn't a correction.");
  // GTFS routes have almost no shapes to compare with.
  if (String(route.correctionOf).startsWith("gtfs:")) return skip(code, "No path to compare in the DOTC 2013 data.");
  if (!facts) return unanswered(code, "the size of this correction");
  if (facts.correction_kept === null) return skip(code, "The route being corrected has no path to compare.");
  const changed = Math.round((1 - facts.correction_kept) * 100);
  return facts.correction_kept >= CORRECTION_KEEP
    ? pass(code, `This changes about ${changed}% of the route.`, { changedPercent: changed })
    : flag(code, `This changes about ${changed}% of the route, so it may be a different route.`, { changedPercent: changed });
}

function checkDrawnGaps(points: Point[]): CheckResult {
  const code = "S_DRAWN_GAPS";
  let longest = 0;
  for (let i = 1; i < points.length; i++) longest = Math.max(longest, metersBetween(points[i - 1], points[i]));
  const meters = Math.round(longest);
  return longest > MAX_STRAIGHT_JUMP_M
    ? flag(code, `Part of the line jumps ${meters} m in a straight line, so it may not follow the road.`, { meters })
    : pass(code, "The line follows the road closely.");
}

function checkNewContributor(context: CheckContext): CheckResult {
  const code = "S_NEW_CONTRIBUTOR";
  if (context.byStaff) return skip(code, "A moderator sent this.");
  const created = context.accountCreatedAt ? Date.parse(context.accountCreatedAt) : NaN;
  const days = Number.isNaN(created) ? 0 : (Date.now() - created) / 86400000;
  if (days < MIN_ACCOUNT_DAYS || context.publishedCount < 1) {
    return flag(code, "New contributors' routes get a moderator's look first.", {
      accountDays: Math.floor(days),
      publishedRoutes: context.publishedCount,
    });
  }
  return pass(code, "This contributor already has a published route.");
}

export function runChecks(route: Route, context: CheckContext): CheckResult[] {
  const points = validPoints(route);
  const { facts, fareRules } = context;
  return [
    checkRequired(route, points),
    checkCoords(route, points),
    checkTarget(route, facts),
    checkRepeat(facts),
    checkFareImpossible(route, points, fareRules),
    checkFareRange(route, points, fareRules),
    checkArea(facts),
    checkOverlap(route, facts),
    checkCorrectionSize(route, facts),
    checkDrawnGaps(points),
    checkNewContributor(context),
  ];
}

/** S_FARE_RANGE on its own. Rider fare reports must pass it before a fare changes. */
export function fareRangeCheck(route: Route, rules: FareRules | null): CheckResult {
  return checkFareRange(route, validPoints(route), rules);
}

export function outcomeOf(results: CheckResult[]): Outcome {
  if (results.some((r) => r.result === "fail")) return "rejected";
  if (results.some((r) => r.result === "flag")) return "pending";
  return "published";
}

// Same value, however its keys were ordered.
function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${stable(v)}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

/** True when a correction changes nothing except a jeepney or bus fare. */
export function isFareOnlyChange(correction: Route, target: Route): boolean {
  if (stable(correction.pathPoints) !== stable(target.pathPoints)) return false;
  const newSteps = stepsOf(correction);
  const oldSteps = stepsOf(target);
  if (newSteps.length === 0 || newSteps.length !== oldSteps.length) return false;

  let changed = false;
  for (let i = 0; i < newSteps.length; i++) {
    const { actualFare: newFare, ...newRest } = newSteps[i];
    const { actualFare: oldFare, ...oldRest } = oldSteps[i];
    if (stable(newRest) !== stable(oldRest)) return false;
    if (newFare !== oldFare) {
      if (!isOfficialFareMode(newSteps[i].mode)) return false;
      changed = true;
    }
  }
  return changed;
}
