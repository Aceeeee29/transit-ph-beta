import { HttpError } from "./http.ts";
import type { Decision, NewRouteRow, RouteRow, RouteStatus } from "./rows.ts";
import type { NewDecision, RoutePatch, RouteStore } from "./store.ts";

const EMPTY_SUMMARY = {
  fareAccurateYes: 0,
  fareAccurateNo: 0,
  scheduleAccurateYes: 0,
  scheduleAccurateNo: 0,
  stillOperatingYes: 0,
  stillOperatingNo: 0,
};

// Newest first, like the real store. Routes with no date go last.
function newestFirst(a: RouteRow, b: RouteRow): number {
  return (b.created_at ?? "").localeCompare(a.created_at ?? "");
}

// For tests only. It gives out copies, so a test can't change a stored row by
// accident and hide a bug.
export class MemoryStore implements RouteStore {
  private routes = new Map<string, RouteRow>();
  decisions: (Decision & { route_id: string; revision: number })[] = [];

  get(id: string): Promise<RouteRow | null> {
    const row = this.routes.get(id);
    return Promise.resolve(row ? structuredClone(row) : null);
  }

  countPending(uid: string, exceptId?: string): Promise<number> {
    const count = [...this.routes.values()].filter((row) =>
      row.contributor_id === uid && row.status === "pending" && row.id !== exceptId
    ).length;
    return Promise.resolve(count);
  }

  insert(row: NewRouteRow): Promise<RouteRow> {
    if (this.routes.has(row.id)) throw new HttpError(409, "conflict");
    const now = new Date().toISOString();
    const stored: RouteRow = {
      verification: "unverified",
      views: 0,
      upvotes: 0,
      downvotes: 0,
      feedback_summary: { ...EMPTY_SUMMARY },
      revision: 1,
      created_at: now,
      updated_at: now,
      published_at: null,
      rejected_at: null,
      ...structuredClone(row),
    };
    this.routes.set(row.id, stored);
    return Promise.resolve(structuredClone(stored));
  }

  update(id: string, patch: RoutePatch, onlyIfStatus?: RouteStatus): Promise<RouteRow | null> {
    const row = this.routes.get(id);
    if (!row || (onlyIfStatus && row.status !== onlyIfStatus)) return Promise.resolve(null);
    const updated: RouteRow = {
      ...row,
      ...structuredClone(patch),
      updated_at: new Date().toISOString(),
    };
    this.routes.set(id, updated);
    return Promise.resolve(structuredClone(updated));
  }

  remove(id: string): Promise<void> {
    this.routes.delete(id);
    return Promise.resolve();
  }

  private list(keep: (row: RouteRow) => boolean): Promise<RouteRow[]> {
    const rows = [...this.routes.values()].filter(keep).sort(newestFirst);
    return Promise.resolve(structuredClone(rows));
  }

  listByContributor(uid: string): Promise<RouteRow[]> {
    return this.list((row) => row.contributor_id === uid);
  }

  listByStatus(status: RouteStatus): Promise<RouteRow[]> {
    return this.list((row) => row.status === status);
  }

  listAll(): Promise<RouteRow[]> {
    return this.list(() => true);
  }

  addDecision(decision: NewDecision): Promise<void> {
    this.decisions.push({ ...structuredClone(decision), created_at: new Date().toISOString() });
    return Promise.resolve();
  }

  latestDecisions(ids: string[]): Promise<Map<string, Decision>> {
    // Later entries replace earlier ones, which also settles equal timestamps.
    const latest = new Map<string, Decision>();
    for (const { route_id, revision: _revision, ...decision } of this.decisions) {
      if (ids.includes(route_id)) latest.set(route_id, structuredClone(decision));
    }
    return Promise.resolve(latest);
  }

  decisionsOfType(decision: string): Promise<(Decision & { route_id: string })[]> {
    return Promise.resolve(
      structuredClone(this.decisions.filter((d) => d.decision === decision)),
    );
  }

  rpc(_name: string, _args: Record<string, unknown>): Promise<unknown> {
    return Promise.reject(new Error("not supported"));
  }
}
