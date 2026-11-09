import { assertEquals, assertRejects } from "jsr:@std/assert@^1.0.0";
import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  type JWTPayload,
  SignJWT,
} from "npm:jose@5.9.6";
import { verifyFirebaseToken } from "./auth.ts";
import { HttpError } from "./http.ts";

const PROJECT = "transitph-75da4";
const ISSUER = `https://securetoken.google.com/${PROJECT}`;

const { publicKey, privateKey } = await generateKeyPair("RS256");
const jwk = { ...(await exportJWK(publicKey)), kid: "test-key", alg: "RS256" };
const keys = createLocalJWKSet({ keys: [jwk] });

type TokenOptions = {
  issuer?: string;
  audience?: string;
  subject?: string | null;
  expiresAt?: string | number | null;
  signWith?: CryptoKey;
};

// Builds a token like Firebase does. Each test changes one thing about it.
function token(options: TokenOptions = {}): Promise<string> {
  const payload: JWTPayload = {};
  let builder = new SignJWT(payload)
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuedAt()
    .setIssuer(options.issuer ?? ISSUER)
    .setAudience(options.audience ?? PROJECT);
  if (options.subject !== null) {
    builder = builder.setSubject(options.subject ?? "uid-1");
  }
  if (options.expiresAt !== null) {
    builder = builder.setExpirationTime(options.expiresAt ?? "1h");
  }
  return builder.sign(options.signWith ?? privateKey);
}

async function assertUnauthenticated(jwt: string) {
  const error = await assertRejects(
    () => verifyFirebaseToken(jwt, { projectId: PROJECT, keys }),
    HttpError,
  );
  assertEquals(error.status, 401);
  assertEquals(error.code, "unauthenticated");
}

Deno.test("valid token gives the uid", async () => {
  const result = await verifyFirebaseToken(await token(), {
    projectId: PROJECT,
    keys,
  });
  assertEquals(result, { uid: "uid-1" });
});

Deno.test("expired token is refused", async () => {
  // An hour in the past, well outside any clock tolerance.
  const past = Math.floor(Date.now() / 1000) - 3600;
  await assertUnauthenticated(await token({ expiresAt: past }));
});

Deno.test("token with no expiry is refused", async () => {
  await assertUnauthenticated(await token({ expiresAt: null }));
});

Deno.test("token for another Firebase project is refused", async () => {
  await assertUnauthenticated(await token({ audience: "other-project" }));
});

Deno.test("token from another issuer is refused", async () => {
  await assertUnauthenticated(
    await token({ issuer: "https://securetoken.google.com/other-project" }),
  );
});

Deno.test("token with no user id is refused", async () => {
  await assertUnauthenticated(await token({ subject: null }));
});

Deno.test("token with an empty user id is refused", async () => {
  await assertUnauthenticated(await token({ subject: "" }));
});

Deno.test("token signed by someone else's key is refused", async () => {
  const other = await generateKeyPair("RS256");
  await assertUnauthenticated(
    await token({ signWith: other.privateKey as CryptoKey }),
  );
});

Deno.test("text that isn't a token is refused", async () => {
  await assertUnauthenticated("not-a-token");
});
