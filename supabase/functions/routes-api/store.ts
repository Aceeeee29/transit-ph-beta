import type { CheckResult, FareRules, RouteFacts } from "./checks.ts";
import type { Issue, IssueStatus } from "./reports.ts";
import type { Decision, NewRouteRow, RouteRow, RouteStatus } from "./rows.ts";

export type NewDecision = Omit<Decision, "created_at"> & {
  route_id: string;
  revision: number;
};

export type RoutePatch = Partial<Omit<RouteRow, "id" | "latest_decision" | "latest_checks">>;

export type FactsRequest = {
  routeId: string;
  contributorId: string | null;
  geom: string | null;
  correctionOf: string | null;
};

export type NewFareRule = {
  mode: string;
  base: number;
  base_km: number;
  per_km: number;
  source: string;
  effective_from?: string;
};

export type FareRuleRow = NewFareRule & { id: number; effective_from: string; created_at: string };

export type NewIssue = Omit<Issue, "id" | "status" | "created_at">;

export type OutdatedRow = { route_key: string; types: string[]; riders: number; since: string; updated_at: string };

// Everything the actions need from the database. Tests use a version that
// lives in memory, so they run without a database.
export interface RouteStore {
  get(id: string): Promise<RouteRow | null>;
  countPending(uid: string, exceptId?: string): Promise<number>;
  countPublished(uid: string): Promise<number>;
  // Throws HttpError(409, "conflict") if the id is already taken.
  insert(row: NewRouteRow): Promise<RouteRow>;
  // With onlyIfStatus, returns null and changes nothing unless the row is at
  // that status. Also returns null if the row doesn't exist.
  update(id: string, patch: RoutePatch, onlyIfStatus?: RouteStatus): Promise<RouteRow | null>;
  remove(id: string): Promise<void>;
  listByContributor(uid: string): Promise<RouteRow[]>;
  listByStatus(status: RouteStatus): Promise<RouteRow[]>;
  listAll(): Promise<RouteRow[]>;
  addDecision(decision: NewDecision): Promise<void>;
  latestDecisions(ids: string[]): Promise<Map<string, Decision>>;
  decisionsOfType(decision: string): Promise<(Decision & { route_id: string })[]>;
  // Replaces what's saved for that revision, so a resend can't leave old results.
  saveChecks(routeId: string, revision: number, checks: CheckResult[]): Promise<void>;
  // Each route's checks for its current revision.
  checksFor(rows: Pick<RouteRow, "id" | "revision">[]): Promise<Map<string, CheckResult[]>>;
  geometryFacts(request: FactsRequest): Promise<RouteFacts>;
  // The newest rule per mode.
  fareRules(): Promise<FareRules>;
  listFareRules(): Promise<FareRuleRow[]>;
  addFareRule(rule: NewFareRule): Promise<FareRuleRow>;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;

  // Rider reports (phase 3).
  // Throws HttpError(409, "already_reported") when this rider already has an
  // open report of this type on this route.
  addIssue(issue: NewIssue): Promise<Issue>;
  // Every open report on one route, of any age. Callers decide what's active.
  openIssues(routeKey: string): Promise<Issue[]>;
  // Every open report on every route, for the moderators' list.
  listOpenIssues(): Promise<Issue[]>;
  countIssuesSince(reporterId: string, since: string): Promise<number>;
  settleIssues(ids: number[], status: Exclude<IssueStatus, "open">, by: string, note: string | null): Promise<void>;
  getOutdated(routeKey: string): Promise<OutdatedRow | null>;
  listOutdated(): Promise<OutdatedRow[]>;
  // Keeps the first "since" when the route was already outdated.
  setOutdated(routeKey: string, types: string[], riders: number): Promise<void>;
  clearOutdated(routeKey: string): Promise<void>;
  // Different riders whose current answer is "still operating".
  operatingRiders(routeId: string): Promise<number>;
  // The newest verified, unverified, auto_verified or auto_unverified decision.
  lastVerificationDecision(routeId: string): Promise<Decision | null>;
  // GTFS route ids to names. Missing ids aren't in the feed.
  gtfsRouteNames(routeIds: string[]): Promise<Map<string, string>>;
}
