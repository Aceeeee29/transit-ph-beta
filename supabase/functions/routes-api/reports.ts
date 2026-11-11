// What riders' reports and confirmations decide on their own. Pure functions,
// so every rule is tested without a database.
//
// A report is about a route's details (fare, path, stops, schedule, still
// running). Road conditions like traffic are a different thing and stay in
// Firestore route_reports.

export const ISSUE_TYPES = [
  "wrong_fare",
  "wrong_path",
  "not_operating",
  "wrong_schedule",
  "wrong_stop",
  "other",
] as const;
export type IssueType = typeof ISSUE_TYPES[number];

export type IssueStatus = "open" | "resolved" | "dismissed";

export type Issue = {
  id: number;
  route_key: string;
  reporter_id: string;
  type: IssueType;
  fare_paid: number | null;
  step_index: number | null;
  note: string | null;
  correction_id: string | null;
  status: IssueStatus;
  created_at: string;
};

/** A report counts for this long. */
export const ACTIVE_DAYS = 30;
/** Different riders with the same kind of report before a route is "Possibly outdated". */
export const OUTDATED_RIDERS = 5;
/** Different riders who must agree on a fare before it changes. */
export const FARE_RIDERS = 3;
/** How far apart, in pesos, fares can be and still count as the same. */
export const FARE_SPREAD = 1;
/** Trust score a route needs before riders can verify it. */
export const VERIFY_TRUST = 60;
/** Different riders who must say it still runs before it's verified. */
export const VERIFY_RIDERS = 3;

const DAY_MS = 86400000;

export function isActive(issue: Pick<Issue, "status" | "created_at">, now = new Date()): boolean {
  if (issue.status !== "open") return false;
  const created = Date.parse(issue.created_at);
  return Number.isFinite(created) && now.getTime() - created < ACTIVE_DAYS * DAY_MS;
}

/**
 * The report types that 5 or more different riders have open on one route,
 * and how many riders are behind the biggest of them. Empty types means the
 * route isn't outdated.
 */
export function outdatedTypes(issues: Issue[], now = new Date()): { types: IssueType[]; riders: number } {
  const riders = new Map<IssueType, Set<string>>();
  for (const issue of issues) {
    if (!isActive(issue, now)) continue;
    const set = riders.get(issue.type) ?? new Set<string>();
    set.add(issue.reporter_id);
    riders.set(issue.type, set);
  }
  const types = ISSUE_TYPES.filter((type) => (riders.get(type)?.size ?? 0) >= OUTDATED_RIDERS);
  const most = Math.max(0, ...types.map((type) => riders.get(type)!.size));
  return { types, riders: most };
}

export type FareAgreement = { stepIndex: number; fare: number; riders: number; issueIds: number[] };

/**
 * Three or more different riders who paid about the same fare (within ₱1 of
 * each other) on the same step. Each rider counts once, with their latest
 * report. The fare is the middle one of the group, rounded to the peso. Null
 * when not enough riders agree.
 */
export function fareAgreement(issues: Issue[], now = new Date()): FareAgreement | null {
  // Latest report per rider and step. Sorting oldest first lets later ones win.
  const latest = new Map<string, Issue>();
  const byAge = [...issues].sort((a, b) => a.created_at.localeCompare(b.created_at));
  for (const issue of byAge) {
    if (issue.type !== "wrong_fare" || !isActive(issue, now)) continue;
    if (typeof issue.fare_paid !== "number" || !(issue.fare_paid > 0)) continue;
    if (typeof issue.step_index !== "number" || issue.step_index < 0) continue;
    latest.set(`${issue.step_index}|${issue.reporter_id}`, issue);
  }

  const bySteps = new Map<number, Issue[]>();
  for (const issue of latest.values()) {
    bySteps.set(issue.step_index!, [...(bySteps.get(issue.step_index!) ?? []), issue]);
  }

  let best: FareAgreement | null = null;
  for (const [stepIndex, stepIssues] of [...bySteps].sort(([a], [b]) => a - b)) {
    const sorted = [...stepIssues].sort((a, b) => a.fare_paid! - b.fare_paid!);
    // The biggest run of fares no more than ₱1 apart.
    let start = 0;
    for (let end = 0; end < sorted.length; end++) {
      while (sorted[end].fare_paid! - sorted[start].fare_paid! > FARE_SPREAD) start++;
      const group = sorted.slice(start, end + 1);
      if (group.length < FARE_RIDERS || (best && group.length <= best.riders)) continue;
      const middle = group[Math.floor((group.length - 1) / 2)].fare_paid!;
      best = { stepIndex, fare: Math.round(middle), riders: group.length, issueIds: group.map((i) => i.id) };
    }
  }
  return best;
}

type Data = Record<string, unknown>;
type Step = Record<string, unknown>;

const isRide = (step: Step) => typeof step?.mode === "string" && step.mode.toLowerCase() !== "walk";

/** The steps a rider pays for, as indexes into steps. */
export function rideIndexes(data: Data): number[] {
  const steps = Array.isArray(data.steps) ? data.steps as Step[] : [];
  return steps.flatMap((step, i) => (isRide(step) ? [i] : []));
}

/**
 * The route with one step's fare changed. The total ("PHP 26") is redone when
 * every ride has a fare, or moved by the difference when the old fare was
 * known. Otherwise it stays, since we can't tell what it was made of.
 */
export function withFare(data: Data, stepIndex: number, fare: number): Data {
  const steps = (Array.isArray(data.steps) ? data.steps as Step[] : []).map((step) => ({ ...step }));
  const oldFare = steps[stepIndex]?.actualFare;
  steps[stepIndex] = { ...steps[stepIndex], actualFare: fare };

  const updated: Data = { ...data, steps };
  const rides = steps.filter(isRide);
  if (rides.length > 0 && rides.every((step) => typeof step.actualFare === "number")) {
    const total = rides.reduce((sum, step) => sum + (step.actualFare as number), 0);
    updated.price = `PHP ${Math.round(total)}`;
  } else if (typeof oldFare === "number" && typeof data.price === "string") {
    const match = data.price.match(/^PHP\s*(\d+(?:\.\d+)?)$/);
    if (match) updated.price = `PHP ${Math.round(Number(match[1]) + fare - oldFare)}`;
  }
  return updated;
}

// Dart's round() goes away from zero on .5, JavaScript's goes up. The app's
// score and this one must agree, so copy Dart.
const roundLikeDart = (value: number) => Math.sign(value) * Math.round(Math.abs(value));

type ScoredRow = {
  status: string;
  feedback_summary: Record<string, unknown>;
  updated_at: string | null;
  created_at: string | null;
};

/**
 * The same 0 to 100 score as RouteTrustService.computeConfidence in the app:
 * 20 for being live or waiting, up to 65 from riders' answers, up to 15 for
 * recent activity.
 */
export function trustScore(row: ScoredRow, now = new Date()): number {
  const approval = row.status === "published" || row.status === "pending" ? 20 : 0;
  const count = (key: string) => {
    const value = Number(row.feedback_summary?.[key] ?? 0);
    return Number.isFinite(value) ? Math.trunc(value) : 0;
  };
  // A question only counts fully once it has 5 answers.
  const points = (yes: number, no: number, max: number) => {
    const total = yes + no;
    if (total <= 0) return 0;
    const weight = Math.min(Math.max(total / 5, 0), 1);
    const value = roundLikeDart(((yes - no) / total) * weight * max);
    return Math.min(Math.max(value, -max), max);
  };
  const confirmations = points(count("fareAccurateYes"), count("fareAccurateNo"), 22) +
    points(count("scheduleAccurateYes"), count("scheduleAccurateNo"), 22) +
    points(count("stillOperatingYes"), count("stillOperatingNo"), 21);

  const reference = Date.parse(row.updated_at ?? row.created_at ?? "");
  let freshness = 0;
  if (Number.isFinite(reference)) {
    const days = Math.floor((now.getTime() - reference) / DAY_MS);
    freshness = days <= 7 ? 15 : days <= 30 ? 10 : days <= 90 ? 5 : 0;
  }
  return Math.min(Math.max(approval + confirmations + freshness, 0), 100);
}

export type VerifyFacts = {
  row: ScoredRow & { verification: string };
  /** Different riders whose current answer is "still operating". */
  operatingRiders: number;
  activeIssues: number;
  outdated: boolean;
  /** A moderator took verification away. Then only a moderator gives it back. */
  unverifiedByStaff: boolean;
};

/** True when riders' confirmations are enough to verify this route. */
export function shouldVerify(facts: VerifyFacts, now = new Date()): boolean {
  const { row } = facts;
  return row.status === "published" &&
    row.verification === "unverified" &&
    !facts.unverifiedByStaff &&
    !facts.outdated &&
    facts.activeIssues === 0 &&
    facts.operatingRiders >= VERIFY_RIDERS &&
    trustScore(row, now) >= VERIFY_TRUST;
}
