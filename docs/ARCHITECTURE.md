# CONECTR architecture

How CONECTR (the app is called **Connector** on your phone) works, and why.
For install and build steps, see the [README](../README.md).

## The split with XPENC

[XPENC](https://github.com/PATILYASHH/XPENC) is deliberately offline: no
`INTERNET` permission, no server, ever. Connector is a **separate** Android
app that holds everything that needs the network, so XPENC's codebase never
touches it.

```
XPENC (offline)                 Connector (online)              GitHub
──────────────────              ───────────────────              ──────
Settings → Backup      ──────▶  reads the JSON file        ──▶  XPENC-BACKUP
writes JSON to the              from the same shared             (private repo,
public "Download/                folder via Android SAF          owned by the
BACKUP XPENC" folder                                              user's own
                                                                   GitHub account)
takes the pulled       ◀──────  leaves the pulled backup   ◀──
backup in                       for XPENC (XpencProvider)
```

Connector never opens XPENC's private database. It only moves the backup
file XPENC already produces and already knows how to import. The two apps
agree on a folder and a small content provider, not on internals.

### Handing a pulled backup to XPENC

After a pull, `XpencInbox` (`lib/core/xpenc/xpenc_inbox.dart`) leaves the
backup in Connector's private storage, and `XpencProvider` (Kotlin) shares it
with XPENC alone. XPENC takes it in by itself and reports the import back the
same way. `SyncState.baseFileSha` records which file this phone's data is
built on, so XPENC can tell whether taking a backup in could lose anything.

Older XPENC versions use the manual route instead: **Import from file** in
XPENC, then **I've imported it** in Connector (or XPENC's "Tell Connector"
link, `lib/core/backup/import_links.dart`).

## Auth

- Sign-in is "Sign in with GitHub", handled entirely by **Supabase Auth**.
- The GitHub OAuth Client ID **and Secret** live in the Supabase dashboard
  (Authentication → Providers → GitHub), not in the app. Only Supabase's
  server does the code exchange.
- On sign-in, Supabase hands the app a GitHub `provider_token` **once**, in
  the redirect, and never re-issues it. `AuthService` stores it immediately
  with `flutter_secure_storage`. Everything else (creating the repo, reading
  and writing the backup) uses that token directly against the GitHub REST
  API.
- The `repo` scope is requested so the token can create and write the private
  `XPENC-BACKUP` repo under the user's own account.
- A single `401` from GitHub isn't trusted. It's retried with any token saved
  meanwhile and confirmed with `GET /user` before the app asks the user to
  reconnect.

## Sync rules

Uploads are **fast-forward only**, never a merge. A phone uploads only if
GitHub's backup is one it already has: its own last upload, or one it pulled
and XPENC confirmed importing.

- File times aren't trusted. XPENC's auto-backup runs whenever XPENC opens,
  so a phone with week-old data writes a brand-new file of it just before
  importing the other phone's backup.
- Each commit records the phone in `Connector-*` trailer lines.
- When GitHub's backup is another phone's, this phone pulls it and holds its
  own uploads until XPENC imports it or the user picks **Keep this phone's
  instead**.
- Connector only uploads files XPENC named itself (`DDMMYYXPENCEBACKUP.json`),
  so it never pushes a restored copy back up.

The rules live in `lib/core/backup/sync_rules.dart`, with tests in
`test/sync_rules_test.dart`.

**Auto-sync** (Settings → Auto-sync) runs as a WorkManager job: every ~15 min
for "After every XPENC backup", otherwise hourly, and whenever Connector
opens.

## Friends and shared entries

Backed by the Supabase tables in [`supabase/migrations/`](../supabase/migrations),
all with Row Level Security.

- **Finding people** is exact-username only (`find_user`). Connector never
  lists or suggests anyone.
- **Requests** go through `send_friend_request`. Asking someone who already
  asked you makes you friends at once. Only the person asked can answer
  (`respond_friend_request`). Cancelling and unfriending delete the row.
- **Declining is quiet**: the sender keeps seeing "Requested".
- **Live**: the Friends tab listens to Realtime while Connector is open.
- **Shared entries** are a ledger between two friends that is the same on
  both sides. The creator proposes an entry, and only the other side accepts
  or rejects it. Accepted entries never change; a mistake is fixed with a
  correcting entry. Entries are made and answered in XPENC; Connector syncs
  them (`lib/core/shared/`) and shows the balance per friend.

Design docs: [`docs/superpowers/specs/`](superpowers/specs).

## Not built yet

- **Encryption for Drive and GitHub.** ExoCloud backups are encrypted on the
  phone; Drive and GitHub ones are still plain JSON in the user's own
  account. The same ExoCloud key could cover them — or XPENC's master
  recovery phrase, rather than a second secret for the user to manage.
- **Starting ExoCloud over without the recovery key.** Losing every phone
  and the recovery key leaves the old backups unreadable, and there's no
  "start fresh" yet: it needs a server function to clear the account's
  ExoCloud rows, since phones can't delete them.
- **ExoCloud billing.** Free during beta, capped at the newest 10 backups of
  up to 10 MB each. A paid tier would raise those caps.
- **Telling a closed phone about a destination switch.** Each phone follows
  a switch the next time Connector opens on it; until then its background
  job keeps using the old destination.
- **Merging.** Two phones with *different* new data can't be combined; one
  side has to win.
- **Instant pull and push notifications.** A new backup or friend request is
  noticed on the next auto-sync or when Connector opens, not the moment it
  happens. That would need a server sending push notifications.
