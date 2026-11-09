// The same check as e2e_whoami.mjs, for accounts that sign in with Google.
// Google sign-in needs a browser, so this serves a small page on localhost.
//
// From the repo root:
//   node supabase/tests/e2e_whoami_google.mjs
// Then open http://localhost:5199 and click the button. Ctrl+C when done.
// To try another action, open http://localhost:5199/?action=my_routes
import { readFileSync } from "node:fs";
import { createServer } from "node:http";

const PORT = Number(process.env.PORT ?? 5199);

function readEnvFile(path) {
  const env = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const at = line.indexOf("=");
    if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return env;
}

// Only the staging URL leaves .env.staging. The page never sees its keys.
const { SUPABASE_URL } = readEnvFile(".env.staging");
if (!SUPABASE_URL) throw new Error("SUPABASE_URL is missing from .env.staging.");

// These values are public. They ship in the app and only identify the project.
const options = readFileSync("lib/firebase_options.dart", "utf8");
const webBlock = options.match(/FirebaseOptions web = FirebaseOptions\(([\s\S]*?)\);/)?.[1];
if (!webBlock) throw new Error("Couldn't find the web config in firebase_options.dart.");
const read = (name) => webBlock.match(new RegExp(`${name}:\\s*'([^']+)'`))?.[1];
const firebaseConfig = {
  apiKey: read("apiKey"),
  appId: read("appId"),
  authDomain: read("authDomain"),
  projectId: read("projectId"),
};

const page = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>routes-api login check</title>
<style>
  body { font: 16px system-ui, sans-serif; max-width: 640px; margin: 48px auto; padding: 0 16px; }
  button { font: inherit; padding: 10px 16px; cursor: pointer; }
  pre { background: #f2f2f2; padding: 12px; white-space: pre-wrap; word-break: break-word; }
</style>
<h1>routes-api login check</h1>
<p>Signs in with Google, then calls the staging function once.</p>
<button id="go">Sign in with Google and test</button>
<pre id="out">Not run yet.</pre>
<script type="module">
  import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
  import {
    getAuth, GoogleAuthProvider, inMemoryPersistence, setPersistence, signInWithPopup, signOut,
  } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";

  const auth = getAuth(initializeApp(${JSON.stringify(firebaseConfig)}));
  const out = document.getElementById("out");
  const action = new URLSearchParams(location.search).get("action") || "whoami";

  document.getElementById("go").onclick = async () => {
    out.textContent = "Signing in...";
    try {
      // Keep the login in memory only, so closing this tab ends it.
      await setPersistence(auth, inMemoryPersistence);
      const { user } = await signInWithPopup(auth, new GoogleAuthProvider());
      out.textContent = "Calling routes-api...";
      const response = await fetch(${JSON.stringify(`${SUPABASE_URL}/functions/v1/routes-api`)}, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + await user.getIdToken(),
        },
        body: JSON.stringify({ action }),
      });
      const text = await response.text();
      let verdict = response.ok ? "OK" : "FAILED";
      if (response.ok && action === "whoami" && JSON.parse(text).data?.uid !== user.uid) {
        verdict = "FAILED: the uid doesn't match the signed-in account.";
      }
      out.textContent =
        "Signed in as uid " + user.uid + "\\nroutes-api answered " + response.status + ": " + text + "\\n" + verdict;
    } catch (error) {
      out.textContent = "FAILED: " + (error.code || error.message);
    } finally {
      await signOut(auth);
    }
  };
</script>
</html>`;

// Firebase allows Google sign-in from "localhost", so listen only there.
createServer((_req, res) => {
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(page);
}).listen(PORT, "localhost", () => {
  console.log(`Open http://localhost:${PORT} and click the button. Ctrl+C when done.`);
});
