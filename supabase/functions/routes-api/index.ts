import { engagement } from "./actions/engagement.ts";
import type { Handler } from "./actions/handler.ts";
import { lifecycle } from "./actions/lifecycle.ts";
import { reports } from "./actions/reports.ts";
import { googleKeys, verifyFirebaseToken } from "./auth.ts";
import { fetchCaller } from "./caller.ts";
import { corsHeaders, HttpError, json } from "./http.ts";
import type { RouteStore } from "./store.ts";
import { SupabaseStore } from "./store_supabase.ts";

const handlers: Record<string, Handler> = {
  // Tells a caller who the server thinks they are. It proves the whole login
  // path works, from the token to the Firestore read.
  whoami: (caller) =>
    Promise.resolve({
      uid: caller.uid,
      role: caller.role,
      blocked: caller.blocked,
    }),
  ...lifecycle,
  ...engagement,
  ...reports,
};

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

let cachedStore: RouteStore | undefined;

// Supabase provides these two to every function automatically.
function store(): RouteStore {
  cachedStore ??= new SupabaseStore(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  );
  return cachedStore;
}

function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new HttpError(401, "unauthenticated");
  return match[1];
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new HttpError(400, "invalid");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new HttpError(400, "invalid");
  }
  return body as Record<string, unknown>;
}

async function handle(req: Request): Promise<unknown> {
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed");

  const projectId = requireEnv("FIREBASE_PROJECT_ID");

  // Check the login first, so a stranger learns nothing about our actions.
  const token = bearerToken(req);
  const { uid } = await verifyFirebaseToken(token, {
    projectId,
    keys: googleKeys(),
  });
  const caller = await fetchCaller(uid, token, projectId);

  const body = await readBody(req);
  const action = typeof body.action === "string" ? body.action : "";
  if (!Object.hasOwn(handlers, action)) {
    throw new HttpError(400, "unknown_action");
  }
  return await handlers[action](caller, body, store());
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  try {
    return json(200, { ok: true, data: await handle(req) });
  } catch (error) {
    if (error instanceof HttpError) {
      return json(error.status, {
        ok: false,
        error: error.code,
        ...error.extra,
      });
    }
    // Details go to the function logs only, never to the caller.
    console.error(error);
    return json(500, { ok: false, error: "internal" });
  }
});
