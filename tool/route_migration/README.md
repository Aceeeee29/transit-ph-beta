# Route migration

Copies route data into Supabase. Firestore is only read. Both scripts are safe to run twice before cutover. **After cutover, don't run `migrate.js` again**, because it would overwrite what riders have changed in Supabase since then.

Run everything from the repo root.

| Step | Command | Writes? |
|---|---|---|
| 1. Refresh the Firebase login | `firebase projects:list` | No |
| 2. Preview | `node tool/route_migration/migrate.js --target staging --dry-run` | No |
| 3. Copy routes | `node tool/route_migration/migrate.js --target staging` | Supabase |
| 4. Load GTFS extras | `node tool/route_migration/gtfs_extras.js --target staging` | Supabase |

Staging reads its keys from `.env.staging`. The live project needs `--target prod --i-mean-live`, with `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` set in the shell. Never save the live service key in a file in this repo.

`gtfs_extras.js` reads `gtfs-master-sakay.ph.zip` from your Downloads folder.

## What the "things to look at" list means

| Name | Meaning | What the script does |
|---|---|---|
| `no_created_at` | The old app's list hid routes with no date, so riders never saw these | Publishes them if approved. **Decide before running on live** |
| `no_path` | Fewer than 2 points | Copies it with no map line |
| `unresolved_owner` | The owner is an email with no matching account | Copies it with no owner, so it never goes to the wrong person |
| `email_in_data` | An email is still in the route's text, such as its description | Copies it. **Fix these before live**, because published rows are public |
| `unknown_status` | A status we don't recognise | Keeps it pending for a moderator |
| `id_mismatch` | The saved `id` field differs from the document's id | Uses the document's id |

Tests: `node --test "tool/route_migration/*.test.js"`
