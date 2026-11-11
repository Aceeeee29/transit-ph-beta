import { assertEquals, assertRejects } from "jsr:@std/assert@^1.0.0";
import { type Caller, fetchCaller, isStaff } from "./caller.ts";
import { HttpError } from "./http.ts";

const DAY_MS = 24 * 60 * 60 * 1000;
const tomorrow = () => new Date(Date.now() + DAY_MS).toISOString();
const yesterday = () => new Date(Date.now() - DAY_MS).toISOString();

// Stands in for Firestore, and remembers what it was asked.
function firestore(status: number, fields: Record<string, unknown> = {}) {
  const calls: { url: string; auth: string | null }[] = [];
  const fetchFn = (input: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(input),
      auth: new Headers(init?.headers).get("Authorization"),
    });
    return Promise.resolve(
      new Response(JSON.stringify({ fields }), { status }),
    );
  };
  return { calls, fetchFn: fetchFn as typeof fetch };
}

function load(status: number, fields: Record<string, unknown> = {}) {
  return fetchCaller("uid-1", "id-token", "proj", firestore(status, fields).fetchFn);
}

Deno.test("reads the user doc with the caller's own token", async () => {
  const { calls, fetchFn } = firestore(200);
  await fetchCaller("uid-1", "id-token", "proj", fetchFn);
  assertEquals(
    calls[0].url,
    "https://firestore.googleapis.com/v1/projects/proj/databases/(default)/documents/users/uid-1",
  );
  assertEquals(calls[0].auth, "Bearer id-token");
});

Deno.test("moderator role is read, and the rider isn't blocked", async () => {
  const caller = await load(200, {
    role: { stringValue: "moderator" },
    name: { stringValue: "Mod" },
  });
  assertEquals(caller, {
    uid: "uid-1",
    role: "moderator",
    blocked: false,
    name: "Mod",
    createdAt: null,
  });
});

Deno.test("the account's age comes from its profile, in either saved form", async () => {
  const timestamp = await load(200, { createdAt: { timestampValue: "2026-01-01T00:00:00Z" } });
  assertEquals(timestamp.createdAt, "2026-01-01T00:00:00Z");
  const text = await load(200, { createdAt: { stringValue: "2026-02-02T00:00:00Z" } });
  assertEquals(text.createdAt, "2026-02-02T00:00:00Z");
});

Deno.test("superadmin role is read", async () => {
  const caller = await load(200, { role: { stringValue: "superadmin" } });
  assertEquals(caller.role, "superadmin");
});

Deno.test("any other role counts as a rider", async () => {
  for (const role of ["user", "admin", ""]) {
    const caller = await load(200, { role: { stringValue: role } });
    assertEquals(caller.role, "rider", `role "${role}"`);
  }
});

Deno.test("isBanned blocks", async () => {
  const caller = await load(200, { isBanned: { booleanValue: true } });
  assertEquals(caller.blocked, true);
});

Deno.test("status banned blocks, ignoring case and spaces like the app", async () => {
  for (const status of ["banned", " Banned "]) {
    const caller = await load(200, { status: { stringValue: status } });
    assertEquals(caller.blocked, true, `status "${status}"`);
  }
});

Deno.test("restriction ending tomorrow blocks", async () => {
  const caller = await load(200, {
    restrictedUntil: { timestampValue: tomorrow() },
  });
  assertEquals(caller.blocked, true);
});

Deno.test("restriction that ended yesterday doesn't block", async () => {
  const caller = await load(200, {
    restrictedUntil: { timestampValue: yesterday() },
  });
  assertEquals(caller.blocked, false);
});

Deno.test("restriction saved as text still blocks", async () => {
  // User.toJson in the app saves this date as text, not a timestamp.
  const caller = await load(200, {
    restrictedUntil: { stringValue: tomorrow() },
  });
  assertEquals(caller.blocked, true);
});

Deno.test("cleared restriction doesn't block", async () => {
  const caller = await load(200, { restrictedUntil: { nullValue: null } });
  assertEquals(caller.blocked, false);
});

Deno.test("no user doc yet means an unblocked rider", async () => {
  const caller = await load(404);
  assertEquals(caller.role, "rider");
  assertEquals(caller.blocked, false);
});

Deno.test("Firestore refusing the token gives 401", async () => {
  for (const status of [401, 403]) {
    const error = await assertRejects(() => load(status), HttpError);
    assertEquals(error.status, 401, `status ${status}`);
  }
});

Deno.test("a Firestore outage refuses the call instead of letting it through", async () => {
  // Without the doc we can't tell if this rider is banned.
  const error = await assertRejects(() => load(503), HttpError);
  assertEquals(error.status, 503);
  assertEquals(error.code, "unavailable");
});

Deno.test("only moderators and superadmins are staff", () => {
  const as = (role: Caller["role"]): Caller => ({
    uid: "u",
    role,
    blocked: false,
    name: "",
    createdAt: null,
  });
  assertEquals(isStaff(as("moderator")), true);
  assertEquals(isStaff(as("superadmin")), true);
  assertEquals(isStaff(as("rider")), false);
});
