import { assertEquals, assertRejects } from "jsr:@std/assert@^1.0.0";
import { engagement } from "./actions/engagement.ts";
import type { Caller } from "./caller.ts";
import { HttpError } from "./http.ts";
import { MemoryStore } from "./store_memory.ts";

const rider: Caller = { uid: "rider-1", role: "rider", blocked: false, name: "", createdAt: null };
const banned: Caller = { ...rider, blocked: true };

// Answers every database call with one fixed result, and remembers the calls.
function storeAnswering(answer: () => unknown) {
  const store = new MemoryStore();
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  store.rpc = (name, args) => {
    calls.push({ name, args });
    return Promise.resolve().then(answer);
  };
  return { store, calls };
}

const failing = (message: string) => () => {
  throw new Error(message);
};

const feedbackBody = {
  routeId: "r1",
  fareAccurate: true,
  scheduleAccurate: false,
  stillOperating: true,
};

async function assertHttp(call: () => Promise<unknown>, status: number, code: string) {
  const error = await assertRejects(call, HttpError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
  return error;
}

Deno.test("open_route: passes the caller's uid, not one the app chose", async () => {
  const { store, calls } = storeAnswering(() => ({ vote: null }));
  const result = await engagement.open_route(rider, { routeId: "r1", userId: "someone-else" }, store);
  assertEquals(result, { vote: null });
  assertEquals(calls, [{ name: "route_open", args: { p_route: "r1", p_user: "rider-1" } }]);
});

Deno.test("open_route: a banned rider can still read a route", async () => {
  const { store } = storeAnswering(() => ({ vote: null }));
  assertEquals(await engagement.open_route(banned, { routeId: "r1" }, store), { vote: null });
});

Deno.test("vote: sends the vote and wraps the answer", async () => {
  const { store, calls } = storeAnswering(() => "up");
  assertEquals(await engagement.vote(rider, { routeId: "r1", up: true }, store), { vote: "up" });
  assertEquals(calls[0], { name: "route_vote", args: { p_route: "r1", p_user: "rider-1", p_up: true } });
});

Deno.test("vote: a removed vote comes back as null", async () => {
  const { store } = storeAnswering(() => null);
  assertEquals(await engagement.vote(rider, { routeId: "r1", up: true }, store), { vote: null });
});

Deno.test("quality_feedback: sends all three answers", async () => {
  const { store, calls } = storeAnswering(() => null);
  // No such route in the store, so nothing to verify.
  assertEquals(await engagement.quality_feedback(rider, feedbackBody, store), { verified: false });
  assertEquals(calls[0], {
    name: "route_quality_feedback",
    args: { p_route: "r1", p_user: "rider-1", p_fare: true, p_schedule: false, p_operating: true },
  });
});

Deno.test("banned riders can't vote or give feedback", async () => {
  const { store, calls } = storeAnswering(() => null);
  await assertHttp(() => engagement.vote(banned, { routeId: "r1", up: true }, store), 403, "blocked");
  await assertHttp(() => engagement.quality_feedback(banned, feedbackBody, store), 403, "blocked");
  assertEquals(calls.length, 0);
});

Deno.test("bad requests never reach the database", async () => {
  const { store, calls } = storeAnswering(() => null);
  await assertHttp(() => engagement.open_route(rider, {}, store), 400, "invalid");
  await assertHttp(() => engagement.vote(rider, { routeId: "r1" }, store), 400, "invalid");
  await assertHttp(() => engagement.vote(rider, { routeId: "r1", up: "yes" }, store), 400, "invalid");
  await assertHttp(() => engagement.vote(rider, { up: true }, store), 400, "invalid");
  await assertHttp(
    () => engagement.quality_feedback(rider, { ...feedbackBody, stillOperating: undefined }, store),
    400,
    "invalid",
  );
  assertEquals(calls.length, 0);
});

Deno.test("switching a vote gives 409 remove_first", async () => {
  const { store } = storeAnswering(failing("remove_first"));
  await assertHttp(() => engagement.vote(rider, { routeId: "r1", up: false }, store), 409, "remove_first");
});

Deno.test("cooldown gives 429 with the next allowed date", async () => {
  const { store } = storeAnswering(failing("feedback_cooldown:2026-12-01T00:00:00.000Z"));
  const error = await assertHttp(() => engagement.quality_feedback(rider, feedbackBody, store), 429, "feedback_cooldown");
  assertEquals(error.extra, { nextAllowedAt: "2026-12-01T00:00:00.000Z" });
});

Deno.test("a missing route gives 404 from every action", async () => {
  const { store } = storeAnswering(failing("route_not_found"));
  await assertHttp(() => engagement.open_route(rider, { routeId: "r1" }, store), 404, "not_found");
  await assertHttp(() => engagement.vote(rider, { routeId: "r1", up: true }, store), 404, "not_found");
  await assertHttp(() => engagement.quality_feedback(rider, feedbackBody, store), 404, "not_found");
});

Deno.test("any other database error stays a server error", async () => {
  // It must not look like something the rider did wrong.
  const { store } = storeAnswering(failing("connection lost"));
  const error = await assertRejects(() => engagement.open_route(rider, { routeId: "r1" }, store), Error);
  assertEquals(error instanceof HttpError, false);
  assertEquals(error.message, "connection lost");
});
