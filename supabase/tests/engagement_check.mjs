// Runs the vote, view and feedback database functions on staging. Their logic
// lives in SQL, so only a real database can test it.
//
// From the repo root: node supabase/tests/engagement_check.mjs
import { readFileSync } from "node:fs";

function readEnvFile(path) {
  const env = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const at = line.indexOf("=");
    if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return env;
}

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY: KEY } = readEnvFile(".env.staging");
if (!SUPABASE_URL || !KEY) {
  console.error("Fill in .env.staging first.");
  process.exit(1);
}
// This test writes rows, so it must never run against the live project.
if (SUPABASE_URL.includes("rruijvorkljjpfkbamls")) {
  console.error("Refusing to run: .env.staging points at the live project.");
  process.exit(1);
}

const ROUTE = "engagement-check-route";
const OLD_ROUTE = "engagement-check-old-route";
const USER = "engagement-check-user";

function rest(path, { method = "GET", body } = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

// Gives back the function's answer, or the database's error message.
async function rpc(name, args) {
  const response = await rest(`rpc/${name}`, { method: "POST", body: args });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : null;
  return response.ok ? { data: parsed } : { error: parsed?.message ?? String(response.status) };
}

async function row(id = ROUTE) {
  const response = await rest(`transit_routes?id=eq.${id}&select=views,upvotes,downvotes,feedback_summary`);
  return (await response.json())[0];
}

let failed = 0;
function check(name, passed, got) {
  if (!passed) failed++;
  console.log(`${passed ? "PASS" : "FAIL"}  ${name}${passed ? "" : `  got: ${JSON.stringify(got)}`}`);
}

async function cleanUp() {
  // Votes, views and feedback go with the route, through the foreign keys.
  await rest(`transit_routes?id=in.(${ROUTE},${OLD_ROUTE})`, { method: "DELETE" });
}

const open = (user = USER, route = ROUTE) => rpc("route_open", { p_route: route, p_user: user });
const vote = (up, user = USER) => rpc("route_vote", { p_route: ROUTE, p_user: user, p_up: up });
const feedback = (route = ROUTE, user = USER, values = [true, false, true]) =>
  rpc("route_quality_feedback", {
    p_route: route,
    p_user: user,
    p_fare: values[0],
    p_schedule: values[1],
    p_operating: values[2],
  });

let stoppedEarly = false;
try {
  await cleanUp();
  const base = { source: "rider", status: "published", data: {} };
  for (const seed of [
    { ...base, id: ROUTE },
    // Old Firestore counters can arrive with some missing.
    { ...base, id: OLD_ROUTE, feedback_summary: { fareAccurateYes: 3 } },
  ]) {
    const seeded = await rest("transit_routes", { method: "POST", body: seed });
    if (!seeded.ok) throw new Error(`Couldn't seed: ${await seeded.text()}`);
  }

  // Views
  const first = await open();
  check("opening a route counts a view", (await row()).views === 1, await row());
  check("a new rider has no vote", first.data?.vote === null, first);
  check("a new rider has no feedback", first.data?.feedback === null, first);
  check("a new rider has no cooldown", first.data?.nextFeedbackAt === null, first);
  check("the summary comes back", first.data?.summary?.fareAccurateYes === 0, first);
  await open();
  check("opening it again doesn't count twice", (await row()).views === 1, await row());
  await open("engagement-check-user-2");
  check("another rider counts", (await row()).views === 2, await row());

  // Votes
  const up = await vote(true);
  check("first vote returns up", up.data === "up", up);
  check("first vote adds 1", (await row()).upvotes === 1, await row());
  check("opening shows the vote", (await open()).data?.vote === "up");
  const undo = await vote(true);
  check("same vote again returns null", undo.data === null, undo);
  check("same vote again takes it away", (await row()).upvotes === 0, await row());
  check("opening shows the vote is gone", (await open()).data?.vote === null);
  await vote(true);
  const flip = await vote(false);
  check("switching a vote needs removing it first", flip.error === "remove_first", flip);
  check("a refused switch changes nothing", (await row()).upvotes === 1 && (await row()).downvotes === 0, await row());
  await vote(true);
  const down = await vote(false);
  check("a down vote returns down", down.data === "down", down);
  check("a down vote adds to downvotes", (await row()).downvotes === 1, await row());

  // Feedback
  const given = await feedback();
  check("feedback is accepted", given.error === undefined, given);
  const summary = (await row()).feedback_summary;
  check(
    "feedback adds to the right counters",
    summary.fareAccurateYes === 1 && summary.fareAccurateNo === 0 &&
      summary.scheduleAccurateYes === 0 && summary.scheduleAccurateNo === 1 &&
      summary.stillOperatingYes === 1 && summary.stillOperatingNo === 0,
    summary,
  );
  check("feedback records when", /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(summary.lastFeedbackAt), summary);

  const again = await feedback();
  const expectedDay = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
  check("a second try within 30 days is refused", again.error?.startsWith("feedback_cooldown:"), again);
  check("the refusal says when it's allowed, in the app's format", again.error?.startsWith(`feedback_cooldown:${expectedDay}T`) && again.error.endsWith("Z"), again);
  check("a refused try doesn't count", (await row()).feedback_summary.fareAccurateYes === 1);

  const opened = await open();
  check(
    "opening shows the rider's feedback",
    opened.data?.feedback?.fareAccurate === true && opened.data?.feedback?.scheduleAccurate === false,
    opened,
  );
  check("opening shows the next allowed date", opened.data?.nextFeedbackAt?.startsWith(expectedDay), opened);

  // Past the 30 days, feedback is allowed again.
  await rest(`route_quality_feedback?route_id=eq.${ROUTE}&user_id=eq.${USER}`, {
    method: "PATCH",
    body: { updated_at: new Date(Date.now() - 31 * 86400000).toISOString() },
  });
  const later = await feedback(ROUTE, USER, [false, true, false]);
  check("feedback works again after 30 days", later.error === undefined, later);
  check("it adds to the counters again", (await row()).feedback_summary.fareAccurateNo === 1, await row());

  // Old routes
  await feedback(OLD_ROUTE);
  const old = (await row(OLD_ROUTE)).feedback_summary;
  check("old counters still add up", Number(old.fareAccurateYes) === 4, old);
  check("missing old counters start from 0", old.scheduleAccurateNo === 1, old);

  // Routes that don't exist
  check("opening a missing route is refused", (await open(USER, "engagement-none")).error === "route_not_found");
  const missingVote = await rpc("route_vote", { p_route: "engagement-none", p_user: USER, p_up: true });
  check("voting on a missing route is refused", missingVote.error === "route_not_found", missingVote);
  check("feedback on a missing route is refused", (await feedback("engagement-none")).error === "route_not_found");

  // Removing a route takes its votes with it.
  await rest(`transit_routes?id=eq.${ROUTE}`, { method: "DELETE" });
  const votesLeft = await (await rest(`route_votes?route_id=eq.${ROUTE}&select=user_id`)).json();
  check("removing a route removes its votes", votesLeft.length === 0, votesLeft);
} catch (error) {
  stoppedEarly = true;
  console.error(`Stopped early: ${error.message}`);
} finally {
  await cleanUp();
}

if (failed > 0 || stoppedEarly) {
  console.error(`ENGAGEMENT FAILED (${failed})`);
  process.exit(1);
}
console.log("ENGAGEMENT OK");
