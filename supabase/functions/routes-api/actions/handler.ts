import type { Caller } from "../caller.ts";
import type { RouteStore } from "../store.ts";

export type Body = Record<string, unknown>;

export type Handler = (caller: Caller, body: Body, store: RouteStore) => Promise<unknown>;
