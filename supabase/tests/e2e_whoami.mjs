// Signs in with a real test account and calls routes-api on staging.
// It proves that a Firebase login works from start to finish, including the
// Firestore read that nothing else can test.
//
// Needs an email and password account. Google sign-in accounts have no password.
//
// PowerShell, from the repo root:
//   $env:TEST_EMAIL='you@example.com'; $env:TEST_PASSWORD='...'; node supabase/tests/e2e_whoami.mjs
// Choose another action with $env:ACTION='my_routes'.
import { readFileSync } from "node:fs";

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readEnvFile(path) {
  const env = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const at = line.indexOf("=");
    if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return env;
}

const { TEST_EMAIL, TEST_PASSWORD, ACTION = "whoami" } = process.env;
if (!TEST_EMAIL || !TEST_PASSWORD) fail("Set TEST_EMAIL and TEST_PASSWORD first.");

const { SUPABASE_URL } = readEnvFile(".env.staging");
if (!SUPABASE_URL) fail("SUPABASE_URL is missing from .env.staging.");

// This key is public. It ships in the app and only identifies the project.
const options = readFileSync("lib/firebase_options.dart", "utf8");
const webKey = options.match(/FirebaseOptions web[\s\S]*?apiKey:\s*'([^']+)'/)?.[1];
if (!webKey) fail("Couldn't find the web API key in lib/firebase_options.dart.");

const signIn = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${webKey}`,
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
      returnSecureToken: true,
    }),
  },
);
const account = await signIn.json();
if (!signIn.ok) fail(`Sign-in failed: ${account.error?.message ?? signIn.status}`);

const response = await fetch(`${SUPABASE_URL}/functions/v1/routes-api`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${account.idToken}`,
  },
  body: JSON.stringify({ action: ACTION }),
});
const text = await response.text();

console.log(`Signed in as uid ${account.localId}`);
console.log(`routes-api answered ${response.status}: ${text}`);

// Checks that the function saw the same person that Firebase signed in.
if (!response.ok) process.exit(1);
if (ACTION === "whoami" && JSON.parse(text).data?.uid !== account.localId) {
  fail("The uid doesn't match the signed-in account.");
}
console.log("OK");
