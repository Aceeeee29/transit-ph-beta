import {
  type CheckContext,
  type CheckResult,
  isFareOnlyChange,
  type Outcome,
  outcomeOf,
  runChecks,
} from "../checks.ts";
import { type Caller, isStaff } from "../caller.ts";
import { HttpError } from "../http.ts";
import { type RouteFromJson, type RouteRow, rowFromRouteJson } from "../rows.ts";
import type { RoutePatch, RouteStore } from "../store.ts";
import type { Body, Handler } from "./handler.ts";
import { settleFixed } from "./reports.ts";

const MAX_PENDING_ROUTES = 3;
const MAX_ID_LENGTH = 128;
const FARE_MODES = new Set(["jeepney", "jeepney_modern", "bus", "bus_aircon", "fx_van", "tricycle"]);

// Same codes as the rejection_reasons table. Only "other" needs a note.
const REJECTION_REASONS = new Set([
  "incomplete",
  "outside_area",
  "wrong_path",
  "wrong_fare",
  "duplicate",
  "not_operating",
  "unsafe_or_spam",
  "other",
]);

// What an approved correction replaces in the route it corrects: the line, its
// steps and the measures that come from them. Votes, reports and the owner stay.
const CORRECTION_KEYS = [
  "pathPoints",
  "stepBoundaries",
  "steps",
  "startLat",
  "startLng",
  "endLat",
  "endLng",
  "distance",
  "distanceMeters",
  "eta",
];

const invalid = () => new HttpError(400, "invalid");
const conflict = () => new HttpError(409, "conflict");

function requireNotBlocked(caller: Caller) {
  if (caller.blocked) throw new HttpError(403, "blocked");
}

// A banned moderator keeps their role in the database, so check both.
function requireStaff(caller: Caller) {
  if (!isStaff(caller)) throw new HttpError(403, "forbidden");
  requireNotBlocked(caller);
}

function requireSuperadmin(caller: Caller) {
  if (caller.role !== "superadmin") throw new HttpError(403, "forbidden");
  requireNotBlocked(caller);
}

const isFilled = (value: unknown) => typeof value === "string" && value.trim() !== "";

// Only a route with no id can't be stored. Anything else wrong with it is the
// checklist's job, so the rider gets a stored rejection saying what to fix. The
// app uses DateTime.now().toString() as the id, so ids can hold spaces and colons.
function routeFromBody(body: Body): Body & { id: string } {
  const route = body.route as Body | undefined;
  if (typeof route !== "object" || route === null || Array.isArray(route)) throw invalid();
  const { id } = route;
  if (typeof id !== "string" || !isFilled(id) || id.length > MAX_ID_LENGTH) throw invalid();
  return route as Body & { id: string };
}

function routeIdFromBody(body: Body): string {
  if (!isFilled(body.routeId)) throw invalid();
  return body.routeId as string;
}

async function requirePendingRoom(store: RouteStore, uid: string, routeId: string) {
  if (await store.countPending(uid, routeId) >= MAX_PENDING_ROUTES) {
    throw new HttpError(409, "pending_limit");
  }
}

async function withDetails(rows: RouteRow[], store: RouteStore): Promise<RouteRow[]> {
  const [decisions, checks] = await Promise.all([
    store.latestDecisions(rows.map((row) => row.id)),
    store.checksFor(rows),
  ]);
  return rows.map((row) => {
    const decision = decisions.get(row.id);
    return {
      ...row,
      ...(decision ? { latest_decision: decision } : {}),
      latest_checks: checks.get(row.id) ?? [],
    };
  });
}

function logDecision(
  store: RouteStore,
  route: Pick<RouteRow, "id" | "revision">,
  actor: Caller | "system",
  decision: string,
  details: { reason_codes?: string[]; note?: string | null } = {},
) {
  return store.addDecision({
    route_id: route.id,
    revision: route.revision,
    actor: actor === "system" ? "system" : actor.uid,
    decision,
    reason_codes: details.reason_codes ?? [],
    note: details.note ?? null,
  });
}

function titleOf(row: RouteRow): string {
  const { startLocation, endLocation } = row.data;
  return startLocation && endLocation ? `${startLocation} to ${endLocation}` : "your submitted route";
}

const editCountOf = (row: RouteRow) => typeof row.data.editCount === "number" ? row.data.editCount : 0;

// One failed lookup must not stop a submission. Each check treats a missing
// answer as "a moderator needs to look", so the route can't go live unchecked.
async function loadContext(
  caller: Caller,
  contributorId: string | null,
  fields: RouteFromJson,
  store: RouteStore,
): Promise<CheckContext> {
  const logged = <T>(what: string, fallback: T) => (error: unknown) => {
    console.error(`Check lookup failed: ${what}`, error);
    return fallback;
  };
  const [facts, fareRules, publishedCount] = await Promise.all([
    store.geometryFacts({
      routeId: fields.id,
      contributorId,
      geom: fields.geom ?? null,
      correctionOf: fields.correction_of,
    }).catch(logged("geometry", null)),
    store.fareRules().catch(logged("fare rules", null)),
    contributorId ? store.countPublished(contributorId).catch(logged("published count", 0)) : Promise.resolve(0),
  ]);
  return { facts, fareRules, publishedCount, accountCreatedAt: caller.createdAt, byStaff: isStaff(caller) };
}

// What each outcome does to a route's row.
function outcomePatch(outcome: Outcome, data: Body): RoutePatch {
  const now = new Date().toISOString();
  if (outcome === "rejected") {
    return { status: "rejected", verification: "unverified", rejected_at: now, data };
  }
  if (outcome === "pending") {
    return { status: "pending", verification: "unverified", rejected_at: null, data };
  }
  return {
    status: "published",
    verification: "unverified",
    published_at: now,
    rejected_at: null,
    data: { ...data, isEdited: false },
  };
}

function logOutcome(store: RouteStore, row: RouteRow, outcome: Outcome, checks: CheckResult[]) {
  if (outcome === "published") return logDecision(store, row, "system", "auto_published");
  const result = outcome === "rejected" ? "fail" : "flag";
  return logDecision(store, row, "system", outcome === "rejected" ? "auto_rejected" : "flagged", {
    reason_codes: checks.filter((c) => c.result === result).map((c) => c.code),
  });
}

// A correction that only fixes a jeepney or bus fare, to an amount in the usual
// range, doesn't need anyone to look. No correction row is kept.
async function applyFareOnlyCorrection(
  route: Body & { id: string },
  checks: CheckResult[],
  store: RouteStore,
) {
  const targetId = route.correctionOf;
  if (typeof targetId !== "string" || targetId.startsWith("gtfs:")) return null;
  if (checks.some((c) => c.result === "fail")) return null;
  if (checks.find((c) => c.code === "S_FARE_RANGE")?.result !== "pass") return null;

  const target = await store.get(targetId);
  if (target?.status !== "published") return null;
  if (!isFareOnlyChange(route, target.data)) return null;

  const data: Body = { ...target.data, steps: route.steps, editCount: editCountOf(target) + 1 };
  if (typeof route.price === "string") data.price = route.price;
  const updated = await store.update(target.id, { data }, "published");
  if (!updated) return null;
  await logDecision(store, updated, "system", "auto_published", {
    note: `fare correction ${route.id} applied`,
  });
  // The fare was fixed, so reports of a wrong fare are answered.
  await settleFixed(store, updated.id, "wrong_fare", "system", `Fare corrected (${route.id}).`);
  return updated;
}

const submit: Handler = async (caller, body, store) => {
  requireNotBlocked(caller);
  const route = routeFromBody(body);
  // The id decides the source, so this stops a modified app from passing a
  // rider route off as a reference route.
  if (route.id.startsWith("osm-") && !isStaff(caller)) throw invalid();

  const existing = await store.get(route.id);
  if (existing && existing.contributor_id !== caller.uid) throw conflict();
  // Editing a route that's live or rejected goes through resubmit.
  if (existing && existing.status !== "pending") throw conflict();

  const fields = rowFromRouteJson(route, caller.uid);
  const checks = runChecks(route, await loadContext(caller, caller.uid, fields, store));

  const applied = await applyFareOnlyCorrection(route, checks, store);
  if (applied) {
    return { id: route.id, outcome: "applied", appliedTo: applied.id, checks, route: applied };
  }

  // Staff are reviewing, so their own routes wait for a second look too.
  const checked = outcomeOf(checks);
  const outcome: Outcome = checked === "published" && isStaff(caller) ? "pending" : checked;
  // The limit is about the moderator queue, so only routes joining it count.
  if (outcome === "pending") await requirePendingRoom(store, caller.uid, route.id);

  const data = { ...fields.data, isEdited: false, editCount: 0, editedAt: null };
  const patch = outcomePatch(outcome, data);
  const contributor_name = caller.name || null;

  // A poor connection can make the app send the same route twice. That
  // shouldn't count as a second route or as an edit.
  let row: RouteRow;
  if (existing) {
    const { id: _id, ...rest } = fields;
    const resent = await store.update(route.id, { ...rest, ...patch, contributor_name }, "pending");
    if (!resent) throw conflict();
    row = resent;
  } else {
    row = await store.insert({ ...fields, ...patch, contributor_name, status: patch.status! });
    await logDecision(store, row, caller, "submitted");
  }
  await store.saveChecks(row.id, row.revision, checks);
  await logOutcome(store, row, outcome, checks);
  return { ...row, outcome, checks };
};

const resubmit: Handler = async (caller, body, store) => {
  requireNotBlocked(caller);
  const route = routeFromBody(body);

  const existing = await store.get(route.id);
  if (!existing) throw new HttpError(404, "not_found");
  const byStaff = isStaff(caller);
  if (existing.contributor_id !== caller.uid && !byStaff) {
    throw new HttpError(403, "forbidden");
  }

  const fields = rowFromRouteJson(route, existing.contributor_id);
  // What a route corrects is fixed when it's first sent. Otherwise an edit could
  // aim it at any other route.
  const checkedRoute: Body & { id: string } = { ...route };
  delete checkedRoute.correctionOf;
  if (existing.correction_of) checkedRoute.correctionOf = existing.correction_of;
  const checks = runChecks(
    checkedRoute,
    await loadContext(caller, existing.contributor_id, { ...fields, correction_of: existing.correction_of }, store),
  );

  // A moderator editing a route is still reviewing it, so it never goes live by
  // itself. Hard fails still apply, so nobody can save an invalid route.
  const checked = outcomeOf(checks);
  const outcome: Outcome = checked === "published" && byStaff ? "pending" : checked;
  // Bringing a route back adds to the rider's queue. Staff edits don't, since
  // the route stays under its contributor and they often edit many.
  if (outcome === "pending" && !byStaff && existing.status !== "pending") {
    await requirePendingRoom(store, caller.uid, route.id);
  }

  const data: Body = {
    ...fields.data,
    isEdited: true,
    editedAt: new Date().toISOString(),
    editCount: editCountOf(existing) + 1,
  };
  delete data.correctionOf;
  if (existing.correction_of) data.correctionOf = existing.correction_of;
  if (existing.data.contributorClosed) data.contributorClosed = true;

  const updated = await store.update(
    route.id,
    {
      ...outcomePatch(outcome, data),
      revision: existing.revision + 1,
      geom: fields.geom,
      start_pt: fields.start_pt,
      end_pt: fields.end_pt,
    },
    existing.status,
  );
  if (!updated) throw conflict();
  await store.saveChecks(updated.id, updated.revision, checks);
  await logDecision(store, updated, caller, "resubmitted");
  await logOutcome(store, updated, outcome, checks);
  return { ...updated, outcome, checks };
};

const myRoutes: Handler = async (caller, _body, store) =>
  await withDetails(await store.listByContributor(caller.uid), store);

const queue: Handler = async (caller, _body, store) => {
  requireStaff(caller);
  return await withDetails(await store.listByStatus("pending"), store);
};

const staffList: Handler = async (caller, _body, store) => {
  requireStaff(caller);
  return await withDetails(await store.listAll(), store);
};

async function mergeCorrection(
  correction: RouteRow,
  target: RouteRow,
  caller: Caller,
  note: string | null,
  store: RouteStore,
) {
  // Claim it first, so a second moderator gets a conflict. "withdrawn" keeps
  // riders from seeing the correction as a duplicate route meanwhile.
  const claimed = await store.update(correction.id, { status: "withdrawn" }, "pending");
  if (!claimed) throw conflict();

  let merged: RouteRow;
  try {
    const data: Body = { ...target.data, editCount: editCountOf(target) + 1 };
    for (const key of CORRECTION_KEYS) {
      if (key in correction.data) data[key] = correction.data[key];
    }
    const { geom, start_pt, end_pt } = rowFromRouteJson({ ...data, id: target.id }, target.contributor_id);
    const updated = await store.update(target.id, { data, geom, start_pt, end_pt }, "published");
    if (!updated) throw conflict();
    merged = updated;
  } catch (error) {
    // Put it back in the queue so a moderator can try again.
    await store.update(correction.id, { status: "pending" }, "withdrawn");
    throw error;
  }

  await store.remove(correction.id);
  const merge = `correction ${correction.id} by ${correction.contributor_id} merged`;
  await logDecision(store, merged, caller, "approved", { note: note ? `${merge}: ${note}` : merge });
  // The line was fixed, so reports of a wrong path are answered.
  await settleFixed(store, merged.id, "wrong_path", caller.uid, `Path corrected (${correction.id}).`);
  return {
    route: merged,
    mergedInto: merged.id,
    contributorId: correction.contributor_id,
    title: titleOf(target),
  };
}

async function approve(row: RouteRow, caller: Caller, note: string | null, store: RouteStore) {
  // Going against the checklist has to be on record, with the reason why.
  const checks = (await store.checksFor([row])).get(row.id) ?? [];
  if (checks.some((c) => c.result === "flag") && !note) throw new HttpError(400, "note_required");

  // A GTFS route has no row here, so that correction stays a route of its own.
  // So does one whose target has been removed.
  const targetId = row.correction_of;
  if (targetId && targetId !== row.id && !targetId.startsWith("gtfs:")) {
    const target = await store.get(targetId);
    if (target?.status === "published") return await mergeCorrection(row, target, caller, note, store);
  }

  const updated = await store.update(
    row.id,
    {
      status: "published",
      // A person looked at it, unlike a route the checks published.
      verification: "verified",
      published_at: new Date().toISOString(),
      rejected_at: null,
      data: { ...row.data, isEdited: false, staleNeedsReview: false },
    },
    "pending",
  );
  if (!updated) throw conflict();
  await logDecision(store, updated, caller, "approved", { note });
  return { route: updated, contributorId: updated.contributor_id, title: titleOf(updated) };
}

async function reject(
  row: RouteRow,
  caller: Caller,
  reasonCodes: unknown,
  note: string | null,
  store: RouteStore,
) {
  if (!Array.isArray(reasonCodes) || reasonCodes.length === 0) throw invalid();
  if (!reasonCodes.every((code) => REJECTION_REASONS.has(code))) throw invalid();
  if (reasonCodes.includes("other") && !note) throw invalid();

  const updated = await store.update(
    row.id,
    { status: "rejected", rejected_at: new Date().toISOString() },
    "pending",
  );
  if (!updated) throw conflict();
  await logDecision(store, updated, caller, "rejected", { reason_codes: reasonCodes, note });
  return { route: updated, contributorId: updated.contributor_id, title: titleOf(updated) };
}

// A person vouching for a live route, or taking that back. It stays live either
// way. Rider confirmations will also do this in phase 3.
async function setVerification(row: RouteRow, caller: Caller, verified: boolean, note: string | null, store: RouteStore) {
  if (row.status !== "published") throw conflict();
  const updated = await store.update(row.id, { verification: verified ? "verified" : "unverified" }, "published");
  if (!updated) throw conflict();
  await logDecision(store, updated, caller, verified ? "verified" : "unverified", { note });
  return { route: updated };
}

const decide: Handler = async (caller, body, store) => {
  requireStaff(caller);
  const routeId = routeIdFromBody(body);
  const { decision, reasonCodes } = body;
  if (!["approve", "reject", "verify", "unverify"].includes(String(decision))) throw invalid();

  const row = await store.get(routeId);
  if (!row) throw new HttpError(404, "not_found");

  const note = typeof body.note === "string" && body.note.trim() ? body.note.trim() : null;
  if (decision === "verify") return await setVerification(row, caller, true, note, store);
  if (decision === "unverify") return await setVerification(row, caller, false, note, store);

  if (row.status !== "pending") throw conflict();
  return decision === "approve"
    ? await approve(row, caller, note, store)
    : await reject(row, caller, reasonCodes, note, store);
};

const deleteRoute: Handler = async (caller, body, store) => {
  requireSuperadmin(caller);
  const routeId = routeIdFromBody(body);
  const row = await store.get(routeId);
  if (!row) throw new HttpError(404, "not_found");
  await store.remove(routeId);
  await logDecision(store, row, caller, "deleted");
  return {};
};

// The dashboard's approval count per moderator. Approving the same route again
// after an edit counts once. A merged correction is its own approval, so its
// note keeps it apart from approvals of the route it merged into.
const moderatorApprovals: Handler = async (caller, _body, store) => {
  requireSuperadmin(caller);
  const byActor = new Map<string, Set<string>>();
  for (const { actor, route_id, note } of await store.decisionsOfType("approved")) {
    if (actor === "system") continue;
    const routes = byActor.get(actor) ?? new Set<string>();
    routes.add(note ? `${route_id}|${note}` : route_id);
    byActor.set(actor, routes);
  }
  return Object.fromEntries([...byActor].map(([actor, routes]) => [actor, [...routes]]));
};

const adminFareRules: Handler = async (caller, _body, store) => {
  requireSuperadmin(caller);
  return await store.listFareRules();
};

// Adds a new row rather than changing one, so past rates stay on record and the
// checks can always say which rate they used.
const adminSetFareRule: Handler = async (caller, body, store) => {
  requireSuperadmin(caller);
  const { mode, base, base_km, per_km, source, effective_from } = body;
  if (typeof mode !== "string" || !FARE_MODES.has(mode)) throw invalid();
  if (typeof base !== "number" || !(base > 0)) throw invalid();
  if (typeof base_km !== "number" || !(base_km >= 0)) throw invalid();
  if (typeof per_km !== "number" || !(per_km >= 0)) throw invalid();
  if (!isFilled(source)) throw invalid();
  if (effective_from !== undefined && (typeof effective_from !== "string" || Number.isNaN(Date.parse(effective_from)))) {
    throw invalid();
  }
  return await store.addFareRule({
    mode,
    base,
    base_km,
    per_km,
    source: (source as string).trim(),
    ...(effective_from ? { effective_from: effective_from as string } : {}),
  });
};

// Banned riders can still leave, so this has no blocked check.
const closeAccount: Handler = async (caller, _body, store) => {
  let released = 0;
  let removed = 0;
  for (const row of await store.listByContributor(caller.uid)) {
    if (row.status === "published") {
      await store.update(row.id, {
        contributor_id: null,
        contributor_name: "Former rider",
        data: { ...row.data, contributorClosed: true },
      });
      released++;
    } else {
      await store.remove(row.id);
      removed++;
    }
  }
  return { released, removed };
};

export const lifecycle: Record<string, Handler> = {
  submit,
  resubmit,
  my_routes: myRoutes,
  queue,
  staff_list: staffList,
  decide,
  delete: deleteRoute,
  close_account: closeAccount,
  moderator_approvals: moderatorApprovals,
  admin_fare_rules: adminFareRules,
  admin_set_fare_rule: adminSetFareRule,
};
