import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { type CheckResult, type FareRules, RULE_VERSION, type RouteFacts } from "./checks.ts";
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

// Leaves out the geometry columns. The path is already in data.
const ROW_COLUMNS =
  "id,source,contributor_id,contributor_name,status,verification,correction_of,data," +
  "views,upvotes,downvotes,feedback_summary,revision,created_at,updated_at,published_at,rejected_at";

const DECISION_COLUMNS = "route_id,decision,reason_codes,note,actor,created_at";

const ISSUE_COLUMNS =
  "id,route_key,reporter_id,type,fare_paid,step_index,note,correction_id,status,created_at";

const OUTDATED_COLUMNS = "route_key,types,riders,since,updated_at";

const VERIFICATION_DECISIONS = ["verified", "unverified", "auto_verified", "auto_unverified"];

// Postgres's code for "this unique key is already taken".
const UNIQUE_VIOLATION = "23505";

// The API returns at most 1,000 rows per request, and more without warning
// would just be missing. So long lists are read a page at a time.
const PAGE_SIZE = 1000;

// A long id list has to fit in one URL.
const IDS_PER_REQUEST = 100;

type QueryResult = { data: unknown; error: { message: string } | null };

async function readAllPages<T>(page: (from: number, to: number) => PromiseLike<QueryResult>): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0;; from += PAGE_SIZE) {
    const { data, error } = await page(from, from + PAGE_SIZE - 1);
    if (error) throw new Error(error.message);
    const batch = (data ?? []) as T[];
    rows.push(...batch);
    if (batch.length < PAGE_SIZE) return rows;
  }
}

// Uses the service role, which can write anywhere. The key is a Supabase
// secret and never reaches the app.
export class SupabaseStore implements RouteStore {
  private client: SupabaseClient;

  constructor(url: string, serviceRoleKey: string) {
    this.client = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  private routes() {
    return this.client.from("transit_routes");
  }

  async get(id: string): Promise<RouteRow | null> {
    const { data, error } = await this.routes().select(ROW_COLUMNS).eq("id", id).maybeSingle();
    if (error) throw new Error(error.message);
    return data as unknown as RouteRow | null;
  }

  async countPending(uid: string, exceptId?: string): Promise<number> {
    let query = this.routes()
      .select("id", { count: "exact", head: true })
      .eq("contributor_id", uid)
      .eq("status", "pending");
    if (exceptId) query = query.neq("id", exceptId);
    const { count, error } = await query;
    if (error) throw new Error(error.message);
    return count ?? 0;
  }

  async countPublished(uid: string): Promise<number> {
    const { count, error } = await this.routes()
      .select("id", { count: "exact", head: true })
      .eq("contributor_id", uid)
      .eq("status", "published");
    if (error) throw new Error(error.message);
    return count ?? 0;
  }

  async saveChecks(routeId: string, revision: number, checks: CheckResult[]): Promise<void> {
    const rows = checks.map((check) => ({
      route_id: routeId,
      revision,
      code: check.code,
      result: check.result,
      message: check.message,
      detail: check.detail,
      rule_version: RULE_VERSION,
      run_at: new Date().toISOString(),
    }));
    const { error } = await this.client.from("route_checks").upsert(rows);
    if (error) throw new Error(error.message);
  }

  async checksFor(rows: Pick<RouteRow, "id" | "revision">[]): Promise<Map<string, CheckResult[]>> {
    const found = new Map<string, CheckResult[]>();
    const revisions = new Map(rows.map((row) => [row.id, row.revision]));
    const ids = [...revisions.keys()];
    for (let start = 0; start < ids.length; start += IDS_PER_REQUEST) {
      const chunk = ids.slice(start, start + IDS_PER_REQUEST);
      const saved = await readAllPages<CheckResult & { route_id: string; revision: number }>((from, to) =>
        this.client
          .from("route_checks")
          .select("route_id,revision,code,result,message,detail")
          .in("route_id", chunk)
          .order("code")
          .range(from, to)
      );
      for (const { route_id, revision, ...check } of saved) {
        if (revisions.get(route_id) !== revision) continue;
        found.set(route_id, [...(found.get(route_id) ?? []), check]);
      }
    }
    return found;
  }

  async geometryFacts(request: FactsRequest): Promise<RouteFacts> {
    return await this.rpc("route_geometry_facts", {
      p_route_id: request.routeId,
      p_contributor: request.contributorId,
      p_geom: request.geom,
      p_correction_of: request.correctionOf,
    }) as RouteFacts;
  }

  async fareRules(): Promise<FareRules> {
    const today = new Date().toISOString().slice(0, 10);
    const { data, error } = await this.client
      .from("fare_rules")
      .select("mode,base,base_km,per_km,source")
      .lte("effective_from", today)
      .order("effective_from", { ascending: false })
      .order("id", { ascending: false });
    if (error) throw new Error(error.message);
    const rules: FareRules = {};
    // Newest comes first, so the first one seen for a mode is the one in use.
    for (const { mode, base, base_km, per_km, source } of data ?? []) {
      rules[mode] ??= { base: Number(base), base_km: Number(base_km), per_km: Number(per_km), source };
    }
    return rules;
  }

  async listFareRules(): Promise<FareRuleRow[]> {
    const { data, error } = await this.client
      .from("fare_rules")
      .select("id,mode,base,base_km,per_km,effective_from,source,created_at")
      .order("effective_from", { ascending: false })
      .order("id", { ascending: false });
    if (error) throw new Error(error.message);
    return (data ?? []) as unknown as FareRuleRow[];
  }

  async addFareRule(rule: NewFareRule): Promise<FareRuleRow> {
    const { data, error } = await this.client
      .from("fare_rules")
      .insert(rule)
      .select("id,mode,base,base_km,per_km,effective_from,source,created_at")
      .single();
    if (error) throw new Error(error.message);
    return data as unknown as FareRuleRow;
  }

  async insert(row: NewRouteRow): Promise<RouteRow> {
    const { data, error } = await this.routes().insert(row).select(ROW_COLUMNS).single();
    if (error?.code === UNIQUE_VIOLATION) throw new HttpError(409, "conflict");
    if (error) throw new Error(error.message);
    return data as unknown as RouteRow;
  }

  async update(id: string, patch: RoutePatch, onlyIfStatus?: RouteStatus): Promise<RouteRow | null> {
    let query = this.routes()
      .update({ ...patch, updated_at: new Date().toISOString() })
      .eq("id", id);
    // Postgres checks this as part of the update, so two decisions at the same
    // moment can't both succeed.
    if (onlyIfStatus) query = query.eq("status", onlyIfStatus);
    const { data, error } = await query.select(ROW_COLUMNS).maybeSingle();
    if (error) throw new Error(error.message);
    return data as unknown as RouteRow | null;
  }

  async remove(id: string): Promise<void> {
    const { error } = await this.routes().delete().eq("id", id);
    if (error) throw new Error(error.message);
  }

  private list(filter?: { column: string; value: string }): Promise<RouteRow[]> {
    return readAllPages<RouteRow>((from, to) => {
      let query = this.routes().select(ROW_COLUMNS);
      if (filter) query = query.eq(filter.column, filter.value);
      // The id keeps the order fixed between pages when dates are equal.
      return query
        .order("created_at", { ascending: false, nullsFirst: false })
        .order("id")
        .range(from, to);
    });
  }

  listByContributor(uid: string): Promise<RouteRow[]> {
    return this.list({ column: "contributor_id", value: uid });
  }

  listByStatus(status: RouteStatus): Promise<RouteRow[]> {
    return this.list({ column: "status", value: status });
  }

  listAll(): Promise<RouteRow[]> {
    return this.list();
  }

  async addDecision(decision: NewDecision): Promise<void> {
    const { error } = await this.client.from("route_decisions").insert(decision);
    if (error) throw new Error(error.message);
  }

  async latestDecisions(ids: string[]): Promise<Map<string, Decision>> {
    const latest = new Map<string, Decision>();
    for (let start = 0; start < ids.length; start += IDS_PER_REQUEST) {
      const chunk = ids.slice(start, start + IDS_PER_REQUEST);
      const rows = await readAllPages<Decision & { route_id: string }>((from, to) =>
        this.client
          .from("route_decisions")
          .select(DECISION_COLUMNS)
          .in("route_id", chunk)
          .order("created_at", { ascending: false })
          .order("id", { ascending: false })
          .range(from, to)
      );
      // Newest comes first, so the first one seen for a route is its latest.
      for (const { route_id, ...decision } of rows) {
        if (!latest.has(route_id)) latest.set(route_id, decision);
      }
    }
    return latest;
  }

  decisionsOfType(decision: string): Promise<(Decision & { route_id: string })[]> {
    return readAllPages<Decision & { route_id: string }>((from, to) =>
      this.client
        .from("route_decisions")
        .select(DECISION_COLUMNS)
        .eq("decision", decision)
        .order("id")
        .range(from, to)
    );
  }

  // Passes the database's own message along, so callers can read codes like
  // "remove_first" out of it.
  async rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.client.rpc(name, args);
    if (error) throw new Error(error.message);
    return data;
  }

  async addIssue(issue: NewIssue): Promise<Issue> {
    const { data, error } = await this.client.from("route_issues").insert(issue).select(ISSUE_COLUMNS).single();
    // The unique index allows one open report per rider, route and type.
    if (error?.code === UNIQUE_VIOLATION) throw new HttpError(409, "already_reported");
    if (error) throw new Error(error.message);
    return toIssue(data);
  }

  async openIssues(routeKey: string): Promise<Issue[]> {
    const rows = await readAllPages<Record<string, unknown>>((from, to) =>
      this.client
        .from("route_issues")
        .select(ISSUE_COLUMNS)
        .eq("route_key", routeKey)
        .eq("status", "open")
        .order("id")
        .range(from, to)
    );
    return rows.map(toIssue);
  }

  async listOpenIssues(): Promise<Issue[]> {
    const rows = await readAllPages<Record<string, unknown>>((from, to) =>
      this.client
        .from("route_issues")
        .select(ISSUE_COLUMNS)
        .eq("status", "open")
        .order("id")
        .range(from, to)
    );
    return rows.map(toIssue);
  }

  async countIssuesSince(reporterId: string, since: string): Promise<number> {
    const { count, error } = await this.client
      .from("route_issues")
      .select("id", { count: "exact", head: true })
      .eq("reporter_id", reporterId)
      .gte("created_at", since);
    if (error) throw new Error(error.message);
    return count ?? 0;
  }

  async settleIssues(ids: number[], status: Exclude<IssueStatus, "open">, by: string, note: string | null): Promise<void> {
    for (let start = 0; start < ids.length; start += IDS_PER_REQUEST) {
      const { error } = await this.client
        .from("route_issues")
        .update({ status, settled_by: by, settled_note: note, settled_at: new Date().toISOString() })
        .in("id", ids.slice(start, start + IDS_PER_REQUEST))
        .eq("status", "open");
      if (error) throw new Error(error.message);
    }
  }

  async getOutdated(routeKey: string): Promise<OutdatedRow | null> {
    const { data, error } = await this.client
      .from("route_outdated")
      .select(OUTDATED_COLUMNS)
      .eq("route_key", routeKey)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data as unknown as OutdatedRow | null;
  }

  listOutdated(): Promise<OutdatedRow[]> {
    return readAllPages<OutdatedRow>((from, to) =>
      this.client.from("route_outdated").select(OUTDATED_COLUMNS).order("route_key").range(from, to)
    );
  }

  async setOutdated(routeKey: string, types: string[], riders: number): Promise<void> {
    const now = new Date().toISOString();
    // Update first, so a route that's been outdated for a while keeps its date.
    const { data, error } = await this.client
      .from("route_outdated")
      .update({ types, riders, updated_at: now })
      .eq("route_key", routeKey)
      .select("route_key");
    if (error) throw new Error(error.message);
    if ((data ?? []).length > 0) return;
    const inserted = await this.client
      .from("route_outdated")
      .upsert({ route_key: routeKey, types, riders, since: now, updated_at: now });
    if (inserted.error) throw new Error(inserted.error.message);
  }

  async clearOutdated(routeKey: string): Promise<void> {
    const { error } = await this.client.from("route_outdated").delete().eq("route_key", routeKey);
    if (error) throw new Error(error.message);
  }

  async operatingRiders(routeId: string): Promise<number> {
    const { count, error } = await this.client
      .from("route_quality_feedback")
      .select("user_id", { count: "exact", head: true })
      .eq("route_id", routeId)
      .eq("still_operating", true);
    if (error) throw new Error(error.message);
    return count ?? 0;
  }

  async lastVerificationDecision(routeId: string): Promise<Decision | null> {
    const { data, error } = await this.client
      .from("route_decisions")
      .select(DECISION_COLUMNS)
      .eq("route_id", routeId)
      .in("decision", VERIFICATION_DECISIONS)
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) return null;
    const { route_id: _routeId, ...decision } = data as unknown as Decision & { route_id: string };
    return decision;
  }

  async gtfsRouteNames(routeIds: string[]): Promise<Map<string, string>> {
    const names = new Map<string, string>();
    for (let start = 0; start < routeIds.length; start += IDS_PER_REQUEST) {
      const { data, error } = await this.client
        .schema("gtfs")
        .from("routes")
        .select("route_id,route_short_name,route_long_name")
        .in("route_id", routeIds.slice(start, start + IDS_PER_REQUEST));
      if (error) throw new Error(error.message);
      for (const row of data ?? []) {
        names.set(String(row.route_id), row.route_long_name || row.route_short_name || String(row.route_id));
      }
    }
    return names;
  }
}

// Postgres numeric comes back as text, so turn the fare back into a number.
function toIssue(row: unknown): Issue {
  const issue = row as Record<string, unknown>;
  return {
    ...(issue as unknown as Issue),
    fare_paid: issue.fare_paid === null || issue.fare_paid === undefined ? null : Number(issue.fare_paid),
  };
}
