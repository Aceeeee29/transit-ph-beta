import { HttpError } from "../http.ts";
import type { RouteStore } from "../store.ts";
import { refreshVerification } from "./reports.ts";
import type { Body, Handler } from "./handler.ts";

const invalid = () => new HttpError(400, "invalid");

function routeIdFrom(body: Body): string {
  if (typeof body.routeId !== "string" || body.routeId.trim() === "") throw invalid();
  return body.routeId;
}

function booleanFrom(body: Body, key: string): boolean {
  const value = body[key];
  if (typeof value !== "boolean") throw invalid();
  return value;
}

// The database functions report problems as plain messages. Turn the ones we
// expect into proper answers. Anything else is a real fault, so let it through
// to become a server error instead of blaming the rider.
function toHttpError(error: unknown): unknown {
  const message = error instanceof Error ? error.message : "";
  if (message === "route_not_found") return new HttpError(404, "not_found");
  if (message === "remove_first") return new HttpError(409, "remove_first");
  if (message.startsWith("feedback_cooldown:")) {
    return new HttpError(429, "feedback_cooldown", {
      nextAllowedAt: message.slice("feedback_cooldown:".length),
    });
  }
  return error;
}

async function callDatabase(store: RouteStore, name: string, args: Record<string, unknown>) {
  try {
    return await store.rpc(name, args);
  } catch (error) {
    throw toHttpError(error);
  }
}

// Every action uses caller.uid. A uid sent by the app is never read, so nobody
// can vote or give feedback as someone else.
export const engagement: Record<string, Handler> = {
  // Banned riders can still read routes, so this has no blocked check.
  open_route: async (caller, body, store) =>
    await callDatabase(store, "route_open", {
      p_route: routeIdFrom(body),
      p_user: caller.uid,
    }),

  vote: async (caller, body, store) => {
    if (caller.blocked) throw new HttpError(403, "blocked");
    const vote = await callDatabase(store, "route_vote", {
      p_route: routeIdFrom(body),
      p_user: caller.uid,
      p_up: booleanFrom(body, "up"),
    });
    return { vote };
  },

  quality_feedback: async (caller, body, store) => {
    if (caller.blocked) throw new HttpError(403, "blocked");
    const routeId = routeIdFrom(body);
    await callDatabase(store, "route_quality_feedback", {
      p_route: routeId,
      p_user: caller.uid,
      p_fare: booleanFrom(body, "fareAccurate"),
      p_schedule: booleanFrom(body, "scheduleAccurate"),
      p_operating: booleanFrom(body, "stillOperating"),
    });
    // Enough riders saying it's right can verify the route. This never fails
    // the rider's answer, which is already saved.
    const verified = await refreshVerification(store, routeId);
    return { verified };
  },
};
