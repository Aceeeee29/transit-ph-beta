export type RouteStatus = "pending" | "published" | "rejected" | "withdrawn";
export type RouteVerification = "unverified" | "verified";
export type RouteSource = "rider" | "osm";

export type Decision = {
  decision: string;
  reason_codes: string[];
  note: string | null;
  actor: string;
  created_at: string;
};

export type RouteRow = {
  id: string;
  source: RouteSource;
  contributor_id: string | null;
  contributor_name: string | null;
  status: RouteStatus;
  verification: RouteVerification;
  correction_of: string | null;
  data: Record<string, unknown>;
  // Only written, not read back. The path is already in data, and lists would
  // otherwise send every route's path twice.
  geom?: string | null;
  start_pt?: string | null;
  end_pt?: string | null;
  views: number;
  upvotes: number;
  downvotes: number;
  feedback_summary: Record<string, unknown>;
  revision: number;
  created_at: string | null;
  updated_at: string | null;
  published_at: string | null;
  rejected_at: string | null;
  latest_decision?: Decision;
  latest_checks?: unknown[];
};

// What a route's JSON decides. Status and verification aren't here on purpose:
// only the server sets those.
export type RouteFromJson = Pick<
  RouteRow,
  | "id"
  | "source"
  | "contributor_id"
  | "contributor_name"
  | "correction_of"
  | "data"
  | "geom"
  | "start_pt"
  | "end_pt"
>;

export type NewRouteRow = RouteFromJson & Partial<RouteRow> & { status: RouteStatus };

// These have their own columns, and the server owns them. Anything the app
// sends for them is ignored, so a modified app can't fake votes or approval.
const SERVER_OWNED = [
  "views",
  "upvotes",
  "downvotes",
  "approvalStatus",
  "createdAt",
  "updatedAt",
  "feedbackSummary",
  "contributorId",
  "contributorName",
  "contributorClosed",
  "verification",
  "revision",
  "latestDecision",
];

// Old routes can hold coordinates as text, and the app accepts that too.
function coordinate(value: unknown, limit: number): number | null {
  if (typeof value !== "number" && typeof value !== "string") return null;
  if (value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) && Math.abs(number) <= limit ? number : null;
}

// PostGIS wants longitude first, the opposite of how we write lat/lng.
function lngLat(lat: unknown, lng: unknown): string | null {
  const y = coordinate(lat, 90);
  const x = coordinate(lng, 180);
  return x === null || y === null ? null : `${x} ${y}`;
}

function point(lat: unknown, lng: unknown): string | null {
  const position = lngLat(lat, lng);
  return position === null ? null : `SRID=4326;POINT(${position})`;
}

function line(pathPoints: unknown): string | null {
  if (!Array.isArray(pathPoints)) return null;
  const positions = pathPoints
    .map((p) => lngLat(p?.lat, p?.lng))
    .filter((position) => position !== null);
  // A bad point shouldn't lose the whole path. Phase 2's checks report it.
  if (positions.length < 2) return null;
  return `SRID=4326;LINESTRING(${positions.join(",")})`;
}

export function rowFromRouteJson(
  json: Record<string, unknown>,
  contributorId: string | null,
): RouteFromJson {
  const data = { ...json };
  for (const key of SERVER_OWNED) delete data[key];

  const id = String(json.id);
  return {
    id,
    source: id.startsWith("osm-") ? "osm" : "rider",
    contributor_id: contributorId,
    contributor_name: typeof json.contributorName === "string" ? json.contributorName : null,
    correction_of: typeof json.correctionOf === "string" ? json.correctionOf : null,
    data,
    geom: line(json.pathPoints),
    start_pt: point(json.startLat, json.startLng),
    end_pt: point(json.endLat, json.endLng),
  };
}
