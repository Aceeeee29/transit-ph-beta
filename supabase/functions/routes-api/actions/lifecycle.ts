import { type Caller, isStaff } from "../caller.ts";
import { HttpError } from "../http.ts";
import { type RouteRow, rowFromRouteJson } from "../rows.ts";
import type { RouteStore } from "../store.ts";
import type { Body, Handler } from "./handler.ts";

const MAX_PENDING_ROUTES = 3;
const MAX_ID_LENGTH = 128;

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

const isFilled = (value: unknown) => typeof value === "string" && value.trim() !== "";

// The app uses DateTime.now().toString() as the id, so ids can hold spaces and
// colons. Don't be stricter than that here.
function routeFromBody(body: Body): Body & { id: string } {
  const route = body.route as Body | undefined;
  if (typeof route !== "object" || route === null || Array.isArray(route)) throw invalid();
  const { id, startLocation, endLocation, steps } = route;
  if (typeof id !== "string" || !isFilled(id) || id.length > MAX_ID_LENGTH) throw invalid();
  if (!isFilled(startLocation) || !isFilled(endLocation)) throw invalid();
  if (!Array.isArray(steps) || steps.length === 0) throw invalid();
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

async function withLatestDecisions(rows: RouteRow[], store: RouteStore): Promise<RouteRow[]> {
  const latest = await store.latestDecisions(rows.map((row) => row.id));
  return rows.map((row) => {
    const decision = latest.get(row.id);
    return decision ? { ...row, latest_decision: decision } : row;
  });
}

function logDecision(
  store: RouteStore,
  route: Pick<RouteRow, "id" | "revision">,
  caller: Caller,
  decision: string,
  details: { reason_codes?: string[]; note?: string | null } = {},
) {
  return store.addDecision({
    route_id: route.id,
    revision: route.revision,
    actor: caller.uid,
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

  await requirePendingRoom(store, caller.uid, route.id);

  const fields = rowFromRouteJson(route, caller.uid);
  const data = { ...fields.data, isEdited: false, editCount: 0, editedAt: null };

  // A poor connection can make the app send the same route twice. That
  // shouldn't count as a second route or as an edit.
  const contributor_name = caller.name || null;
  if (existing) {
    const { id: _id, ...patch } = fields;
    const resent = await store.update(route.id, { ...patch, data, contributor_name }, "pending");
    if (!resent) throw conflict();
    return resent;
  }

  const inserted = await store.insert({
    ...fields,
    data,
    contributor_name,
    status: "pending",
    verification: "unverified",
  });
  await logDecision(store, inserted, caller, "submitted");
  return inserted;
};

const resubmit: Handler = async (caller, body, store) => {
  requireNotBlocked(caller);
  const route = routeFromBody(body);

  const existing = await store.get(route.id);
  if (!existing) throw new HttpError(404, "not_found");
  if (existing.contributor_id !== caller.uid && !isStaff(caller)) {
    throw new HttpError(403, "forbidden");
  }
  // Bringing a route back adds to the rider's queue. Staff edits don't, since
  // the route stays under its contributor and they often edit many.
  if (!isStaff(caller) && existing.status !== "pending") {
    await requirePendingRoom(store, caller.uid, route.id);
  }

  const fields = rowFromRouteJson(route, existing.contributor_id);
  const data: Body = {
    ...fields.data,
    isEdited: true,
    editedAt: new Date().toISOString(),
    editCount: editCountOf(existing) + 1,
  };
  // What a route corrects is fixed when it's first sent. Otherwise an edit could
  // aim it at any other route.
  delete data.correctionOf;
  if (existing.correction_of) data.correctionOf = existing.correction_of;
  if (existing.data.contributorClosed) data.contributorClosed = true;

  const updated = await store.update(
    route.id,
    {
      status: "pending",
      revision: existing.revision + 1,
      data,
      geom: fields.geom,
      start_pt: fields.start_pt,
      end_pt: fields.end_pt,
      rejected_at: null,
    },
    existing.status,
  );
  if (!updated) throw conflict();
  await logDecision(store, updated, caller, "resubmitted");
  return updated;
};

const myRoutes: Handler = async (caller, _body, store) =>
  await withLatestDecisions(await store.listByContributor(caller.uid), store);

const queue: Handler = async (caller, _body, store) => {
  requireStaff(caller);
  return await withLatestDecisions(await store.listByStatus("pending"), store);
};

const staffList: Handler = async (caller, _body, store) => {
  requireStaff(caller);
  return await withLatestDecisions(await store.listAll(), store);
};

async function mergeCorrection(
  correction: RouteRow,
  target: RouteRow,
  caller: Caller,
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
  await logDecision(store, merged, caller, "approved", {
    note: `correction ${correction.id} by ${correction.contributor_id} merged`,
  });
  return {
    route: merged,
    mergedInto: merged.id,
    contributorId: correction.contributor_id,
    title: titleOf(target),
  };
}

async function approve(row: RouteRow, caller: Caller, note: string | null, store: RouteStore) {
  // A GTFS route has no row here, so that correction stays a route of its own.
  // So does one whose target has been removed.
  const targetId = row.correction_of;
  if (targetId && targetId !== row.id && !targetId.startsWith("gtfs:")) {
    const target = await store.get(targetId);
    if (target?.status === "published") return await mergeCorrection(row, target, caller, store);
  }

  const updated = await store.update(
    row.id,
    {
      status: "published",
      // A person looked at it. Phase 2's automatic publishing won't set this.
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

const decide: Handler = async (caller, body, store) => {
  requireStaff(caller);
  const routeId = routeIdFromBody(body);
  const { decision, reasonCodes } = body;
  if (decision !== "approve" && decision !== "reject") throw invalid();

  const row = await store.get(routeId);
  if (!row) throw new HttpError(404, "not_found");
  if (row.status !== "pending") throw conflict();

  const note = typeof body.note === "string" && body.note.trim() ? body.note.trim() : null;
  return decision === "approve"
    ? await approve(row, caller, note, store)
    : await reject(row, caller, reasonCodes, note, store);
};

const deleteRoute: Handler = async (caller, body, store) => {
  if (caller.role !== "superadmin") throw new HttpError(403, "forbidden");
  requireNotBlocked(caller);
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
  if (caller.role !== "superadmin") throw new HttpError(403, "forbidden");
  requireNotBlocked(caller);
  const byActor = new Map<string, Set<string>>();
  for (const { actor, route_id, note } of await store.decisionsOfType("approved")) {
    if (actor === "system") continue;
    const routes = byActor.get(actor) ?? new Set<string>();
    routes.add(note ? `${route_id}|${note}` : route_id);
    byActor.set(actor, routes);
  }
  return Object.fromEntries([...byActor].map(([actor, routes]) => [actor, [...routes]]));
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
};
