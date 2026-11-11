import type { CheckResult, FareRules, RouteFacts } from "./checks.ts";
import { HttpError } from "./http.ts";
import type { Decision, NewRouteRow, RouteRow, RouteStatus } from "./rows.ts";
import type { Issue, IssueStatus } from "./reports.ts";
import type {
  FactsRequest,
  FareRuleRow,
  NewDecision,
  NewFareRule,
  NewIssue,
  OutdatedRow,
  RoutePatch,
  RouteStore,
} from "./store.ts";

const NO_FACTS: RouteFacts = {
  target_exists: null,
  target_status: null,
  length_km: 1,
  camanava_km: 5,
  published_overlap: null,
  gtfs_overlap: null,
  repeat: null,
  correction_kept: null,
};

const VERIFICATION_DECISIONS = ["verified", "unverified", "auto_verified", "auto_unverified"];

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
  private checks = new Map<string, CheckResult[]>();
  private fareRows: FareRuleRow[] = [];

  // Tests set these to shape what the map and fare lookups answer.
  facts: RouteFacts = { ...NO_FACTS };
  factsError: Error | null = null;
  rules: FareRules | Error = {
    jeepney: { base: 14, base_km: 4, per_km: 1.94, source: "TransitPH estimate" },
    bus: { base: 18, base_km: 5, per_km: 2.22, source: "TransitPH estimate" },
    bus_aircon: { base: 18, base_km: 5, per_km: 3.18, source: "TransitPH estimate" },
    fx_van: { base: 40, base_km: 5, per_km: 4.57, source: "TransitPH estimate" },
    tricycle: { base: 16, base_km: 2, per_km: 5.33, source: "TransitPH estimate" },
  };
  lastFactsRequest: FactsRequest | null = null;

  issues: Issue[] = [];
  outdated = new Map<string, OutdatedRow>();
  // Tests set how many riders say each route still runs, and the GTFS names.
  operating = new Map<string, number>();
  gtfsNames = new Map<string, string>();
  issuesError: Error | null = null;

  addIssue(issue: NewIssue): Promise<Issue> {
    const taken = this.issues.some((i) =>
      i.status === "open" && i.route_key === issue.route_key && i.reporter_id === issue.reporter_id &&
      i.type === issue.type
    );
    if (taken) return Promise.reject(new HttpError(409, "already_reported"));
    const saved: Issue = {
      ...structuredClone(issue),
      id: this.issues.length + 1,
      status: "open",
      created_at: new Date().toISOString(),
    };
    this.issues.push(saved);
    return Promise.resolve(structuredClone(saved));
  }

  openIssues(routeKey: string): Promise<Issue[]> {
    if (this.issuesError) return Promise.reject(this.issuesError);
    return Promise.resolve(structuredClone(this.issues.filter((i) => i.route_key === routeKey && i.status === "open")));
  }

  listOpenIssues(): Promise<Issue[]> {
    return Promise.resolve(structuredClone(this.issues.filter((i) => i.status === "open")));
  }

  countIssuesSince(reporterId: string, since: string): Promise<number> {
    const count = this.issues.filter((i) => i.reporter_id === reporterId && i.created_at >= since).length;
    return Promise.resolve(count);
  }

  settleIssues(ids: number[], status: Exclude<IssueStatus, "open">, _by: string, _note: string | null): Promise<void> {
    for (const issue of this.issues) {
      if (ids.includes(issue.id) && issue.status === "open") issue.status = status;
    }
    return Promise.resolve();
  }

  getOutdated(routeKey: string): Promise<OutdatedRow | null> {
    const row = this.outdated.get(routeKey);
    return Promise.resolve(row ? structuredClone(row) : null);
  }

  listOutdated(): Promise<OutdatedRow[]> {
    return Promise.resolve(structuredClone([...this.outdated.values()]));
  }

  setOutdated(routeKey: string, types: string[], riders: number): Promise<void> {
    const now = new Date().toISOString();
    const since = this.outdated.get(routeKey)?.since ?? now;
    this.outdated.set(routeKey, { route_key: routeKey, types: [...types], riders, since, updated_at: now });
    return Promise.resolve();
  }

  clearOutdated(routeKey: string): Promise<void> {
    this.outdated.delete(routeKey);
    return Promise.resolve();
  }

  operatingRiders(routeId: string): Promise<number> {
    return Promise.resolve(this.operating.get(routeId) ?? 0);
  }

  lastVerificationDecision(routeId: string): Promise<Decision | null> {
    const found = this.decisions.filter((d) => d.route_id === routeId && VERIFICATION_DECISIONS.includes(d.decision));
    const last = found.at(-1);
    if (!last) return Promise.resolve(null);
    const { route_id: _r, revision: _v, ...decision } = last;
    return Promise.resolve(structuredClone(decision));
  }

  gtfsRouteNames(routeIds: string[]): Promise<Map<string, string>> {
    return Promise.resolve(new Map([...this.gtfsNames].filter(([id]) => routeIds.includes(id))));
  }

  countPublished(uid: string): Promise<number> {
    const count = [...this.routes.values()].filter((row) => row.contributor_id === uid && row.status === "published").length;
    return Promise.resolve(count);
  }

  saveChecks(routeId: string, revision: number, checks: CheckResult[]): Promise<void> {
    this.checks.set(`${routeId}|${revision}`, structuredClone(checks));
    return Promise.resolve();
  }

  checksFor(rows: Pick<RouteRow, "id" | "revision">[]): Promise<Map<string, CheckResult[]>> {
    const found = new Map<string, CheckResult[]>();
    for (const { id, revision } of rows) {
      const checks = this.checks.get(`${id}|${revision}`);
      if (checks) found.set(id, structuredClone(checks));
    }
    return Promise.resolve(found);
  }

  geometryFacts(request: FactsRequest): Promise<RouteFacts> {
    this.lastFactsRequest = request;
    return this.factsError ? Promise.reject(this.factsError) : Promise.resolve(structuredClone(this.facts));
  }

  fareRules(): Promise<FareRules> {
    return this.rules instanceof Error ? Promise.reject(this.rules) : Promise.resolve(structuredClone(this.rules));
  }

  listFareRules(): Promise<FareRuleRow[]> {
    return Promise.resolve(structuredClone(this.fareRows));
  }

  addFareRule(rule: NewFareRule): Promise<FareRuleRow> {
    const row: FareRuleRow = {
      effective_from: new Date().toISOString().slice(0, 10),
      ...rule,
      id: this.fareRows.length + 1,
      created_at: new Date().toISOString(),
    };
    this.fareRows.unshift(row);
    return Promise.resolve(structuredClone(row));
  }

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
