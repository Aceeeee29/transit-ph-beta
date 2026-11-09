import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { HttpError } from "./http.ts";
import type { Decision, NewRouteRow, RouteRow, RouteStatus } from "./rows.ts";
import type { NewDecision, RoutePatch, RouteStore } from "./store.ts";

// Leaves out the geometry columns. The path is already in data.
const ROW_COLUMNS =
  "id,source,contributor_id,contributor_name,status,verification,correction_of,data," +
  "views,upvotes,downvotes,feedback_summary,revision,created_at,updated_at,published_at,rejected_at";

const DECISION_COLUMNS = "route_id,decision,reason_codes,note,actor,created_at";

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
}
