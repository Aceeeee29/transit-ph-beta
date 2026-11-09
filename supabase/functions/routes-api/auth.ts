import {
  createRemoteJWKSet,
  jwtVerify,
  type JWTVerifyGetKey,
} from "npm:jose@5.9.6";
import { HttpError } from "./http.ts";

const GOOGLE_KEYS_URL = new URL(
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
);

let cachedKeys: JWTVerifyGetKey | undefined;

// Kept between calls so we don't download Google's keys on every request.
export function googleKeys(): JWTVerifyGetKey {
  cachedKeys ??= createRemoteJWKSet(GOOGLE_KEYS_URL);
  return cachedKeys;
}

// Supabase can't check Firebase logins on our plan, so we check them here.
// Every failure is the same 401, so the app knows to get a fresh token and
// try once more.
export async function verifyFirebaseToken(
  token: string,
  opts: { projectId: string; keys: JWTVerifyGetKey },
): Promise<{ uid: string }> {
  let uid: string | undefined;
  try {
    const { payload } = await jwtVerify(token, opts.keys, {
      issuer: `https://securetoken.google.com/${opts.projectId}`,
      audience: opts.projectId,
      algorithms: ["RS256"],
      // jose only checks these when asked. A token with no expiry would
      // otherwise work forever.
      requiredClaims: ["exp", "sub"],
    });
    uid = payload.sub;
  } catch {
    throw new HttpError(401, "unauthenticated");
  }
  if (!uid) throw new HttpError(401, "unauthenticated");
  return { uid };
}
