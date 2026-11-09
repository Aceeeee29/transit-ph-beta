// Proves that someone holding only the public anon key can read published
// routes and nothing else. Run it after every schema change.
//
// From the repo root: node supabase/tests/rls_check.mjs
import { readFileSync } from "node:fs";

function readEnvFile(path) {
  const env = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const at = line.indexOf("=");
    if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return env;
}

const { SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY } = readEnvFile(".env.staging");
if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Fill in all 3 values in .env.staging first.");
  process.exit(1);
}

const PUBLISHED = "rls-check-published";
const PENDING = "rls-check-pending";

function call(key, path, { method = "GET", body, prefer } = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

const anon = (path, options) => call(SUPABASE_ANON_KEY, path, options);
const admin = (path, options) => call(SUPABASE_SERVICE_ROLE_KEY, path, options);

async function adminOk(path, options) {
  const response = await admin(path, options);
  if (!response.ok) {
    throw new Error(`Setup call failed, ${path}: ${response.status} ${await response.text()}`);
  }
  return response;
}

async function publishedRow() {
  const response = await adminOk(`transit_routes?id=eq.${PUBLISHED}&select=upvotes,status`);
  return (await response.json())[0];
}

async function cleanUp() {
  // Votes go with the route, through the foreign key.
  await admin(`transit_routes?id=in.(${PUBLISHED},${PENDING})`, { method: "DELETE" });
  await admin(`transit_routes?id=eq.rls-check-intruder`, { method: "DELETE" });
}

const results = [];
function check(name, passed, detail = "") {
  results.push(passed);
  console.log(`${passed ? "PASS" : "FAIL"}  ${name}${detail ? ` (${detail})` : ""}`);
}

let failedToRun = false;
try {
  await cleanUp();
  const route = {
    source: "rider",
    data: {},
    // A real line, so reading it also proves anon can use the PostGIS types.
    geom: "SRID=4326;LINESTRING(120.98 14.65, 120.99 14.66)",
  };
  await adminOk("transit_routes", {
    method: "POST",
    body: [
      { ...route, id: PUBLISHED, status: "published" },
      { ...route, id: PENDING, status: "pending" },
    ],
  });
  await adminOk("route_votes", {
    method: "POST",
    body: { route_id: PUBLISHED, user_id: "rls-check-user", vote: "up" },
  });

  // 1. Reads see published routes only.
  const read = await anon(`transit_routes?id=in.(${PUBLISHED},${PENDING})&select=id,geom`);
  const readRows = read.ok ? await read.json() : [];
  check(
    "anon reads published routes, not pending ones",
    read.ok && readRows.length === 1 && readRows[0].id === PUBLISHED,
    `http ${read.status}, ${readRows.length} row(s)`,
  );

  // 2. Inserts are refused.
  const insert = await anon("transit_routes", {
    method: "POST",
    body: { id: "rls-check-intruder", source: "rider", status: "published", data: {} },
  });
  const intruder = await (await adminOk("transit_routes?id=eq.rls-check-intruder&select=id")).json();
  check(
    "anon can't add a route",
    (insert.status === 401 || insert.status === 403) && intruder.length === 0,
    `http ${insert.status}`,
  );

  // 3. Private tables stay private. A vote exists, so an empty answer means something.
  const votes = await anon(`route_votes?route_id=eq.${PUBLISHED}`);
  const voteRows = votes.ok ? await votes.json() : [];
  check("anon can't read votes", voteRows.length === 0, `http ${votes.status}`);

  // 4. Database functions are refused.
  const before = await publishedRow();
  const rpc = await anon("rpc/route_vote", {
    method: "POST",
    body: { p_route: PUBLISHED, p_user: "rls-check-intruder", p_up: true },
  });
  const after = await publishedRow();
  check(
    "anon can't call route_vote",
    !rpc.ok && after.upvotes === before.upvotes,
    `http ${rpc.status}`,
  );

  // 5. Published routes can't be changed or removed.
  await anon(`transit_routes?id=eq.${PUBLISHED}`, {
    method: "PATCH",
    body: { status: "rejected" },
  });
  await anon(`transit_routes?id=eq.${PUBLISHED}`, { method: "DELETE" });
  const survivor = await publishedRow();
  check(
    "anon can't change or delete a published route",
    survivor?.status === "published",
    `status now ${survivor?.status ?? "deleted"}`,
  );
} catch (error) {
  failedToRun = true;
  console.error(error.message);
} finally {
  await cleanUp();
}

const passed = results.filter(Boolean).length;
if (failedToRun || passed !== 5) {
  console.error(`RLS FAILED (${passed}/5)`);
  process.exit(1);
}
console.log("RLS OK (5/5)");
