import { fareRangeCheck } from "../checks.ts";
import { type Caller, isStaff } from "../caller.ts";
import { HttpError } from "../http.ts";
import {
  fareAgreement,
  type Issue,
  ISSUE_TYPES,
  type IssueType,
  isActive,
  outdatedTypes,
  rideIndexes,
  shouldVerify,
  trustScore,
  withFare,
} from "../reports.ts";
import type { RouteRow } from "../rows.ts";
import type { OutdatedRow, RouteStore } from "../store.ts";
import type { Body, Handler } from "./handler.ts";

const MAX_KEY_LENGTH = 140;
const MAX_NOTE_LENGTH = 500;
const MAX_FARE = 1000;
const REPORTS_PER_DAY = 20;
const DAY_MS = 86400000;

const invalid = () => new HttpError(400, "invalid");

const isGtfs = (routeKey: string) => routeKey.startsWith("gtfs:");

const peso = (amount: number) => `₱${Math.round(amount * 100) / 100}`;

function noteFrom(body: Body): string | null {
  if (body.note === undefined || body.note === null) return null;
  if (typeof body.note !== "string") throw invalid();
  const note = body.note.trim();
  if (note.length > MAX_NOTE_LENGTH) throw invalid();
  return note || null;
}

// A label is only as fresh as the reports behind it. Reports count for 30 days,
// so a label nobody has touched in that long no longer holds.
export function isOutdatedNow(row: OutdatedRow | null, now = new Date()): boolean {
  if (!row || row.types.length === 0) return false;
  const updated = Date.parse(row.updated_at);
  return Number.isFinite(updated) && now.getTime() - updated < 30 * DAY_MS;
}

function logSystem(store: RouteStore, row: RouteRow, decision: string, note: string) {
  return store.addDecision({
    route_id: row.id,
    revision: row.revision,
    actor: "system",
    decision,
    reason_codes: [],
    note,
  });
}

/**
 * Verifies a live, unverified route when riders' confirmations are enough.
 * Any lookup that fails leaves the route as it is: riders can't verify a route
 * we couldn't check.
 */
export async function refreshVerification(store: RouteStore, routeId: string): Promise<boolean> {
  try {
    const row = await store.get(routeId);
    if (!row || row.status !== "published" || row.verification !== "unverified") return false;
    const [issues, outdated, operatingRiders, last] = await Promise.all([
      store.openIssues(routeId),
      store.getOutdated(routeId),
      store.operatingRiders(routeId),
      store.lastVerificationDecision(routeId),
    ]);
    const facts = {
      row,
      operatingRiders,
      activeIssues: issues.filter((issue) => isActive(issue)).length,
      outdated: isOutdatedNow(outdated),
      // Only "unverified" is a person's choice. The others are verify or automatic.
      unverifiedByStaff: last?.decision === "unverified",
    };
    if (!shouldVerify(facts)) return false;
    const updated = await store.update(routeId, { verification: "verified" }, "published");
    if (!updated) return false;
    await logSystem(
      store,
      updated,
      "auto_verified",
      `Trust ${trustScore(row)}/100 and ${operatingRiders} riders say it still runs.`,
    );
    return true;
  } catch (error) {
    console.error("Verification check failed", error);
    return false;
  }
}

/**
 * Changes a fare when enough riders paid the same amount. Only for jeepney and
 * bus rides on live routes, and only to an amount S_FARE_RANGE accepts, the
 * same as a fare-only correction. Returns the ids of the reports it settled.
 */
async function applyFareAgreement(store: RouteStore, row: RouteRow, issues: Issue[]): Promise<number[]> {
  const agreement = fareAgreement(issues);
  if (!agreement) return [];
  const steps = Array.isArray(row.data.steps) ? row.data.steps as Record<string, unknown>[] : [];
  const step = steps[agreement.stepIndex];
  const mode = typeof step?.mode === "string" ? step.mode.toLowerCase() : "";
  if (mode !== "jeepney" && mode !== "bus") return [];

  const current = step.actualFare;
  if (current === agreement.fare) {
    await store.settleIssues(agreement.issueIds, "resolved", "system", "The route already has this fare.");
    return agreement.issueIds;
  }

  const data = withFare(row.data, agreement.stepIndex, agreement.fare);
  const rules = await store.fareRules().catch((error) => {
    console.error("Fare rules lookup failed", error);
    return null;
  });
  if (fareRangeCheck({ ...data, id: row.id }, rules).result !== "pass") return [];

  const editCount = typeof row.data.editCount === "number" ? row.data.editCount : 0;
  const updated = await store.update(row.id, { data: { ...data, editCount: editCount + 1 } }, "published");
  if (!updated) return [];
  const before = typeof current === "number" ? peso(current) : "no fare";
  await logSystem(
    store,
    updated,
    "fare_updated",
    `Step ${agreement.stepIndex + 1}: ${before} to ${peso(agreement.fare)}, from ${agreement.riders} riders' reports.`,
  );
  await store.settleIssues(agreement.issueIds, "resolved", "system", `Fare changed to ${peso(agreement.fare)}.`);
  return agreement.issueIds;
}

export type ReviewResult = { outdated: IssueType[]; fareChanged: boolean };

/**
 * Looks at a route's open reports and does what they add up to: a fare fix,
 * the "Possibly outdated" label (which also takes verification away), or
 * clearing that label once the reports behind it are gone.
 */
export async function reviewReports(store: RouteStore, routeKey: string): Promise<ReviewResult> {
  let issues = await store.openIssues(routeKey);
  const row = isGtfs(routeKey) ? null : await store.get(routeKey);
  // Reports never change a route someone is reviewing, or one that's not live.
  const live = row?.status === "published" ? row : null;

  let fareChanged = false;
  if (live) {
    const settled = await applyFareAgreement(store, live, issues);
    fareChanged = settled.length > 0;
    if (fareChanged) issues = issues.filter((issue) => !settled.includes(issue.id));
  }

  const { types, riders } = outdatedTypes(issues);
  const before = await store.getOutdated(routeKey);
  if (types.length > 0) {
    await store.setOutdated(routeKey, types, riders);
    const current = live ? await store.get(live.id) : null;
    if (current && !isOutdatedNow(before)) {
      await logSystem(store, current, "outdated", `Possibly outdated: ${riders} riders reported ${types.join(", ")}.`);
    }
    if (current?.status === "published" && current.verification === "verified") {
      const unverified = await store.update(current.id, { verification: "unverified" }, "published");
      if (unverified) await logSystem(store, unverified, "auto_unverified", "Riders say it may be out of date.");
    }
  } else if (before) {
    await store.clearOutdated(routeKey);
  }

  if (live) await refreshVerification(store, live.id);
  return { outdated: types, fareChanged };
}

/** Settles one kind of report after the route was fixed, then looks again. */
export async function settleFixed(
  store: RouteStore,
  routeKey: string,
  type: IssueType,
  by: string,
  note: string,
): Promise<void> {
  try {
    const ids = (await store.openIssues(routeKey)).filter((issue) => issue.type === type).map((issue) => issue.id);
    if (ids.length > 0) await store.settleIssues(ids, "resolved", by, note);
    await reviewReports(store, routeKey);
  } catch (error) {
    // The fix itself is already saved, so don't fail it over this.
    console.error("Settling reports failed", error);
  }
}

async function requireReportable(store: RouteStore, routeKey: string): Promise<RouteRow | null> {
  if (isGtfs(routeKey)) {
    const id = routeKey.slice("gtfs:".length);
    if (!id) throw invalid();
    try {
      const names = await store.gtfsRouteNames([id]);
      if (!names.has(id)) throw new HttpError(404, "not_found");
    } catch (error) {
      if (error instanceof HttpError) throw error;
      // The feed couldn't be read. A report is harmless, so take it anyway.
      console.error("GTFS lookup failed", error);
    }
    return null;
  }
  const row = await store.get(routeKey);
  if (!row) throw new HttpError(404, "not_found");
  if (row.status !== "published") throw new HttpError(409, "not_live");
  return row;
}

// Which ride a fare report is about. A route with one ride doesn't need to say.
function stepFrom(body: Body, row: RouteRow | null): number | null {
  if (!row) return null;
  const rides = rideIndexes(row.data);
  if (body.stepIndex === undefined || body.stepIndex === null) {
    if (rides.length === 1) return rides[0];
    throw invalid();
  }
  if (typeof body.stepIndex !== "number" || !rides.includes(body.stepIndex)) throw invalid();
  return body.stepIndex;
}

const reportIssue: Handler = async (caller, body, store) => {
  if (caller.blocked) throw new HttpError(403, "blocked");
  const routeKey = body.routeId;
  if (typeof routeKey !== "string" || !routeKey.trim() || routeKey.length > MAX_KEY_LENGTH) throw invalid();
  const type = body.type as IssueType;
  if (!ISSUE_TYPES.includes(type)) throw invalid();
  const note = noteFrom(body);
  if (type === "other" && !note) throw invalid();

  const row = await requireReportable(store, routeKey);

  let farePaid: number | null = null;
  let stepIndex: number | null = null;
  if (type === "wrong_fare") {
    const fare = body.farePaid;
    if (typeof fare !== "number" || !(fare > 0) || fare > MAX_FARE) throw invalid();
    farePaid = fare;
    stepIndex = stepFrom(body, row);
  }

  // A drawn fix must be the rider's own correction of this route.
  let correctionId: string | null = null;
  if (type === "wrong_path" && body.correctionId !== undefined && body.correctionId !== null) {
    if (typeof body.correctionId !== "string") throw invalid();
    const correction = await store.get(body.correctionId);
    if (!correction || correction.contributor_id !== caller.uid || correction.correction_of !== routeKey) {
      throw invalid();
    }
    correctionId = correction.id;
  }

  const since = new Date(Date.now() - DAY_MS).toISOString();
  if (await store.countIssuesSince(caller.uid, since) >= REPORTS_PER_DAY) {
    throw new HttpError(429, "report_limit");
  }

  const issue = await store.addIssue({
    route_key: routeKey,
    reporter_id: caller.uid,
    type,
    fare_paid: farePaid,
    step_index: stepIndex,
    note,
    correction_id: correctionId,
  });

  // The report is saved even if what it adds up to can't be worked out now.
  // The next report or a moderator will look again.
  let review: ReviewResult = { outdated: [], fareChanged: false };
  try {
    review = await reviewReports(store, routeKey);
  } catch (error) {
    console.error("Reviewing reports failed", error);
  }
  return { id: issue.id, outdated: review.outdated.length > 0, fareChanged: review.fareChanged };
};

function requireStaff(caller: Caller) {
  if (!isStaff(caller)) throw new HttpError(403, "forbidden");
  if (caller.blocked) throw new HttpError(403, "blocked");
}

const titleOf = (row: RouteRow) => {
  const { startLocation, endLocation } = row.data;
  return startLocation && endLocation ? `${startLocation} to ${endLocation}` : row.id;
};

// Every route with active reports, the outdated ones first, then by how many
// riders reported it.
const issueQueue: Handler = async (caller, _body, store) => {
  requireStaff(caller);
  const now = new Date();
  const byRoute = new Map<string, Issue[]>();
  for (const issue of await store.listOpenIssues()) {
    if (!isActive(issue, now)) continue;
    byRoute.set(issue.route_key, [...(byRoute.get(issue.route_key) ?? []), issue]);
  }
  const outdated = new Map((await store.listOutdated()).map((row) => [row.route_key, row]));
  const keys = [...byRoute.keys()];
  const gtfsIds = keys.filter(isGtfs).map((key) => key.slice("gtfs:".length));
  const names = gtfsIds.length > 0
    ? await store.gtfsRouteNames(gtfsIds).catch(() => new Map<string, string>())
    : new Map<string, string>();

  const entries = await Promise.all(keys.map(async (key) => {
    const issues = byRoute.get(key)!;
    const row = isGtfs(key) ? null : await store.get(key);
    const label = outdated.get(key);
    const counts: Record<string, number> = {};
    for (const type of ISSUE_TYPES) {
      const riders = new Set(issues.filter((i) => i.type === type).map((i) => i.reporter_id)).size;
      if (riders > 0) counts[type] = riders;
    }
    const gtfsId = key.slice("gtfs:".length);
    return {
      routeKey: key,
      source: isGtfs(key) ? "gtfs" : row?.source ?? null,
      title: row ? titleOf(row) : isGtfs(key) ? names.get(gtfsId) ?? gtfsId : key,
      route: row,
      outdated: isOutdatedNow(label ?? null, now) ? { types: label!.types, riders: label!.riders, since: label!.since } : null,
      counts,
      riders: new Set(issues.map((i) => i.reporter_id)).size,
      issues: issues.map(({ route_key: _key, ...issue }) => issue),
    };
  }));
  return entries.sort((a, b) => Number(!!b.outdated) - Number(!!a.outdated) || b.riders - a.riders);
};

// A moderator checked a route's reports: "resolved" when it was fixed or is
// right after all, "dismissed" when the reports were wrong.
const settleIssues: Handler = async (caller, body, store) => {
  requireStaff(caller);
  const routeKey = body.routeId;
  if (typeof routeKey !== "string" || !routeKey.trim()) throw invalid();
  const resolution = body.resolution;
  if (resolution !== "resolved" && resolution !== "dismissed") throw invalid();
  const note = noteFrom(body);

  const ids = (await store.openIssues(routeKey)).map((issue) => issue.id);
  if (ids.length > 0) await store.settleIssues(ids, resolution, caller.uid, note);
  await store.clearOutdated(routeKey);

  const row = isGtfs(routeKey) ? null : await store.get(routeKey);
  if (row) {
    await store.addDecision({
      route_id: row.id,
      revision: row.revision,
      actor: caller.uid,
      decision: `reports_${resolution}`,
      reason_codes: [],
      note,
    });
    await refreshVerification(store, row.id);
  }
  return { settled: ids.length };
};

export const reports: Record<string, Handler> = {
  report_issue: reportIssue,
  issue_queue: issueQueue,
  settle_issues: settleIssues,
};
