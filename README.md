# Connector

The online half of [XPENC](../Money-Management). XPENC is deliberately offline
— no `INTERNET` permission, no server, ever. Connector is a **separate**
Android app that backs XPENC's own JSON export up to a private GitHub repo
(`XPENC-BACKUP`) and pulls it back down on another device, without XPENC's
codebase ever touching the network.

## How it fits together

```
XPENC (offline)                 Connector (online)              GitHub
──────────────────              ───────────────────              ──────
Settings → Backup      ──────▶  reads the JSON file        ──▶  XPENC-BACKUP
writes JSON to the              from the same shared             (private repo,
public "Download/                folder via Android SAF          owned by the
BACKUP XPENC" folder                                              user's own
                                                                   GitHub account)
Settings → Restore     ◀──────  writes the pulled JSON     ◀──
picks the file XPENC                back into that folder
already knows how to
import
```

Connector never opens XPENC's private database. It only ever moves the file
XPENC already produces and already knows how to import — the two apps agree
on a folder, not on internals.

## Auth model

- Sign-in is "Sign in with GitHub", handled entirely by **Supabase Auth**.
- The GitHub OAuth Client ID **and Secret** live in the Supabase dashboard
  (Authentication → Providers → GitHub), not in this app. The app never sees
  the secret — only Supabase's server does the code exchange.
- On successful sign-in, Supabase hands the app a GitHub `provider_token`
  **once**, in the redirect. That's the only chance to capture it — Supabase
  does not re-issue it on later launches — so `AuthService` persists it
  immediately via `flutter_secure_storage`. Everything else (creating the
  repo, reading/writing the backup file) uses that stored token directly
  against the GitHub REST API.
- The `repo` OAuth scope is requested so the token can create and write to
  the private `XPENC-BACKUP` repo under the signed-in user's account.

## One-time setup (do this before running)

### 1. Create a Supabase project
Already done for this app — see `dart_define.local.json` (gitignored, not
committed) for the project URL and anon key currently in use.

### 2. Register a GitHub OAuth App
GitHub → Settings → Developer settings → OAuth Apps → New OAuth App:
- **Homepage URL**: anything, e.g. `https://xpenc.in`
- **Authorization callback URL**: your Supabase project's callback URL,
  shown on the GitHub provider page in the Supabase dashboard (looks like
  `https://<project-ref>.supabase.co/auth/v1/callback`)

This gives you a **Client ID** and **Client Secret**.

### 3. Configure the GitHub provider in Supabase
Supabase dashboard → Authentication → Providers → GitHub:
- Paste the Client ID and Client Secret from step 2.
- Under Authentication → URL Configuration, add
  `conectr://login-callback` to the **Redirect URLs** allow-list — this
  must match `AppConfig.githubOAuthRedirect` in
  `lib/core/config/app_config.dart` and the intent-filter in
  `android/app/src/main/AndroidManifest.xml`.

### 4. Run it
```sh
flutter run --dart-define-from-file=dart_define.local.json
```
`dart_define.local.json` holds `SUPABASE_URL` and `SUPABASE_ANON_KEY` — copy
`dart_define.example.json` if you need to point at a different project. The
anon key is safe to ship in a client (public by design, gated by Supabase's
Row Level Security); **never** put a `service_role` key in this app — it
bypasses RLS entirely and this project has no need for it, since Connector
never talks to a custom database, only to Supabase Auth and the GitHub API
directly.

## First run, on each device

1. Sign in with GitHub.
2. Point Connector at XPENC's `Download/BACKUP XPENC` folder (create a
   backup in XPENC first if that folder doesn't exist yet).
3. **Upload now** pushes the newest local JSON backup to the
   `XPENC-BACKUP` repo. **Pull latest** pulls the newest one from GitHub
   back into that folder as `xpenc_backup.json` — then open XPENC →
   Settings → Backup & Restore → **Import from file** and pick it to
   actually import it into the app's database, and tap **I've imported
   it** back in Connector. (XPENC's own Restore list only shows files it
   named itself, `DDMMYYXPENCEBACKUP.json`, so the pulled file won't appear
   there — and Connector only ever uploads files matching that name, so it
   never pushes its own restored copy back up.)
4. On a second phone, GitHub already holds the first phone's backup, so
   Connector pulls it and won't upload until you either import it or pick
   **Keep this phone's instead**.

## Friends

Run each file in `supabase/migrations/` once, in order, in the Supabase
SQL Editor (the project isn't on the CLI account). `…0002_friends.sql`
adds the `friendships` table this tab needs.

- **Finding people** is exact-username only (`find_user`) — Connector never
  lists or suggests anyone.
- **Requests** go through `send_friend_request`; asking someone who already
  asked you makes you friends at once. Only the person asked can answer
  (`respond_friend_request`). Cancelling and unfriending delete the row.
- **Declining is quiet**: the sender keeps seeing "Requested".
- **Live**: the tab listens to Realtime while Connector is open and re-reads
  the list on every change and on every return to the app.
- **Shared owes & dues** between friends are phases 3–4 of
  `docs/superpowers/specs/2026-10-24-friends-shared-dues-design.md` — not
  built yet.

## Not yet built (flagged, not silently skipped)

- **Friend-request notifications.** A request shows up live while
  Connector is open, and as a badge on the Friends tab the next time it
  opens — there's no push notification when it's closed.

- **Encryption before upload.** The backup currently goes to GitHub as
  plain JSON. Even in a private repo, that's a new trust dependency XPENC's
  "no server, ever" pitch didn't have before. Worth encrypting client-side
  before push — XPENC's existing master-recovery-phrase infrastructure
  (`lib/features/security/master_phrase_*`) would be a natural key source,
  reused rather than inventing a second secret for the user to manage.
- **Conflict handling.** Fast-forward only, not merge: a phone uploads
  only if GitHub's backup is one it already has — its own last upload, or
  one it pulled and the user confirmed importing ("I've imported it"). File
  times aren't trusted for this: XPENC's auto-backup runs whenever XPENC
  opens, so a phone with week-old data writes a brand-new file of it just
  before importing the other phone's backup. Each commit records the phone
  in `Connector-*` trailer lines. When GitHub's backup is another phone's,
  this phone pulls it and holds its own uploads until the user imports it
  or picks "Keep this phone's instead". Two phones with *different* new
  data still can't be combined — that would need real merge logic.
- **Instant pull.** Auto-sync (Settings → Auto-sync) runs as a WorkManager
  job — every ~15 min for "After every XPENC backup", otherwise hourly —
  and whenever Connector opens. Learning about a new backup the moment
  it's pushed would need a server sending push notifications.
- **Auto-import.** A pulled backup only lands in the folder; importing it
  stays a manual step in XPENC, since it replaces all of XPENC's data.
