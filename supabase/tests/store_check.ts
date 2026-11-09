// Runs SupabaseStore against the real staging database. The unit tests use the
// in-memory store, so only this proves the real queries work.
//
// From the repo root:
//   npx -y deno@2 run --node-modules-dir=none --no-lock --allow-net --allow-read=.env.staging --allow-env supabase/tests/store_check.ts
import { rowFromRouteJson } from "../functions/routes-api/rows.ts";
import { HttpError } from "../functions/routes-api/http.ts";
import { SupabaseStore } from "../functions/routes-api/store_supabase.ts";

const env: Record<string, string> = {};
for (const line of (await Deno.readTextFile(".env.staging")).split(/\r?\n/)) {
  const at = line.indexOf("=");
  if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
}

// This test writes rows, so it must never run against the live project.
if (env.SUPABASE_URL.includes("rruijvorkljjpfkbamls")) {
  console.error("Refusing to run: .env.staging points at the live project.");
  Deno.exit(1);
}

const store = new SupabaseStore(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
const USER = "store-check-user";
const R1 = "store-check-1";
const R2 = "store-check-2";
const R3 = "store-check-3";

let failed = 0;
function check(name: string, passed: boolean, detail: unknown = "") {
  if (!passed) failed++;
  console.log(`${passed ? "PASS" : "FAIL"}  ${name}${passed ? "" : `  got: ${JSON.stringify(detail)}`}`);
}

async function cleanUp() {
  for (const id of [R1, R2, R3]) await store.remove(id);
  // Decisions outlive their route on purpose, so delete test ones directly.
  const response = await fetch(
    `${env.SUPABASE_URL}/rest/v1/route_decisions?route_id=in.(${R1},${R2},${R3})`,
    {
      method: "DELETE",
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  if (!response.ok) console.error(`Couldn't clean up decisions: ${response.status}`);
}

const route = (id: string, extra: Record<string, unknown> = {}) => ({
  ...rowFromRouteJson(
    {
      id,
      startLocation: "A",
      pathPoints: [{ lat: 14.65, lng: 120.98 }, { lat: 14.66, lng: 120.99 }],
      startLat: 14.65,
      startLng: 120.98,
      endLat: 14.66,
      endLng: 120.99,
    },
    USER,
  ),
  status: "pending" as const,
  ...extra,
});

try {
  await cleanUp();

  const inserted = await store.insert(route(R1));
  check("insert returns the row with database defaults", inserted.views === 0 && inserted.revision === 1, inserted);
  check("rows don't send the geometry back", !("geom" in inserted), Object.keys(inserted));

  let duplicate: unknown;
  try {
    await store.insert(route(R1));
  } catch (error) {
    duplicate = error;
  }
  check(
    "inserting a taken id gives 409 conflict",
    duplicate instanceof HttpError && duplicate.status === 409 && duplicate.code === "conflict",
    String(duplicate),
  );

  check("get finds a row", (await store.get(R1))?.id === R1);
  check("get returns null for no row", (await store.get("store-check-none")) === null);

  await store.insert(route(R2));
  await store.insert(route(R3, { status: "published" }));
  check("countPending counts pending only", (await store.countPending(USER)) === 2);
  check("countPending can skip one", (await store.countPending(USER, R1)) === 1);

  const first = await store.update(R1, { status: "published" }, "pending");
  const second = await store.update(R1, { status: "rejected" }, "pending");
  check("first conditional update wins", first?.status === "published", first);
  check("second conditional update changes nothing", second === null, second);
  check("the first decision stands", (await store.get(R1))?.status === "published");
  check("updating a missing row returns null", (await store.update("store-check-none", { revision: 2 })) === null);

  const mine = await store.listByContributor(USER);
  check("listByContributor finds all 3", mine.length === 3, mine.map((r) => r.id));
  const pending = await store.listByStatus("pending");
  check("listByStatus filters by status", pending.some((r) => r.id === R2) && !pending.some((r) => r.id === R1));
  const all = await store.listAll();
  check("listAll includes every status", [R1, R2, R3].every((id) => all.some((r) => r.id === id)));

  const decide = (route_id: string, decision: string, reason_codes: string[] = []) =>
    store.addDecision({ route_id, revision: 1, actor: USER, decision, reason_codes, note: null });
  await decide(R1, "rejected", ["wrong_fare"]);
  await decide(R1, "approved");
  await decide(R2, "rejected", ["other"]);
  const latest = await store.latestDecisions([R1, R2, R3]);
  check("latest decision wins", latest.get(R1)?.decision === "approved", latest.get(R1));
  check("reason codes come back", latest.get(R2)?.reason_codes[0] === "other", latest.get(R2));
  check("a route with no decisions has no entry", !latest.has(R3));
  const approvals = await store.decisionsOfType("approved");
  check(
    "decisionsOfType finds that type only",
    approvals.some((d) => d.route_id === R1) && !approvals.some((d) => d.route_id === R2),
    approvals,
  );

  const opened = await store.rpc("route_open", { p_route: R1, p_user: USER }) as Record<string, unknown>;
  check("rpc reaches the database functions", opened.vote === null, opened);
  let rpcError = "";
  try {
    await store.rpc("route_open", { p_route: "store-check-none", p_user: USER });
  } catch (error) {
    rpcError = (error as Error).message;
  }
  check("rpc passes on the database's error code", rpcError === "route_not_found", rpcError);

  await store.remove(R2);
  check("remove deletes the row", (await store.get(R2)) === null);

  // The app's real ids have spaces, colons and dots, so they must survive the
  // trip through URLs and filters.
  const realId = "2026-11-09 14:30:00.123456";
  await store.remove(realId);
  await store.insert(route(realId));
  check("an id in the app's format can be read", (await store.get(realId))?.id === realId);
  await decide(realId, "submitted");
  const forRealId = await store.latestDecisions([realId, R3]);
  check("an id in the app's format works in a list filter", forRealId.get(realId)?.decision === "submitted");
  await store.remove(realId);
  await fetch(
    `${env.SUPABASE_URL}/rest/v1/route_decisions?route_id=eq.${encodeURIComponent(realId)}`,
    {
      method: "DELETE",
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  check("an id in the app's format can be removed", (await store.get(realId)) === null);
} catch (error) {
  failed++;
  console.error(`Stopped early: ${(error as Error).message}`);
} finally {
  await cleanUp();
}

if (failed > 0) {
  console.error(`STORE FAILED (${failed})`);
  Deno.exit(1);
}
console.log("STORE OK");
