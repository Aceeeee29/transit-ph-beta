import type { Decision, NewRouteRow, RouteRow, RouteStatus } from "./rows.ts";

export type NewDecision = Omit<Decision, "created_at"> & {
  route_id: string;
  revision: number;
};

export type RoutePatch = Partial<Omit<RouteRow, "id" | "latest_decision">>;

// Everything the actions need from the database. Tests use a version that
// lives in memory, so they run without a database.
export interface RouteStore {
  get(id: string): Promise<RouteRow | null>;
  countPending(uid: string, exceptId?: string): Promise<number>;
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
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
}
