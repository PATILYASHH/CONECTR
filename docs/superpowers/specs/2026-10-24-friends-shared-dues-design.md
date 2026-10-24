# Friends & shared dues — design

Status: approved 2026-10-24. Spans two repos: Connector (this one) and
XPENC (`../Money-Management`).

## Goal

Connector users get a unique username, sign in with GitHub or email, find
each other by exact username, and become friends. Friends share an
owes/dues ledger that is the same number on both sides, updates live, and
shows up in each user's XPENC Persons screen — while the XPENC app itself
keeps no INTERNET permission.

## Decisions

| Question | Decision |
|---|---|
| Where dues are entered and viewed | In XPENC. Connector relays them to/from Supabase on-device. |
| When an entry counts | Only after the other friend accepts it — on both sides. |
| Existing XPENC balance when linking a person | One opening entry for the current balance, accepted like any other. Old history stays private. |
| XPENC ↔ Connector bridge | Android ContentProvider in Connector (approach A). Not shared files, not broadcasts. |
| Username rules | 3–20 chars, `a–z 0–9 _`, stored lowercase, unique. |
| Username search | Exact match only, via RPC — no listing users. |
| Email login | 6-digit email code (OTP). No passwords. |
| Editing | Creator may edit/delete while pending. Accepted entries are immutable; fix with a correcting entry. |
| Repayment | A normal entry in the opposite direction. The account it moved through stays local to each XPENC. |
| Unfriending | Deletes the friendship and its shared entries on the server; both XPENCs keep their entries as plain local ones. |

## Privacy statement

XPENC never connects to the internet (Android enforces this — no INTERNET
permission; `tool/verify_apk.sh` checks every release). Dues and notes for a
person the user links to a Connector friend are stored on Supabase via the
separate Connector app. Nothing leaves the phone if Connector isn't
installed or no person is linked. PRIVACY.md and the link screen say so.

## 1. Supabase

Migrations live in `supabase/migrations/`, one per phase, pasted into the
SQL editor (the project isn't on the CLI account).

Tables, all with RLS on and nothing granted to `anon`:

- `profiles(id → auth.users, username, display_name, created_at)`. Read:
  self, plus accepted friends (phase 2). Insert/update: self only.
- `friendships(id, requester_id, addressee_id, status pending|accepted|declined, created_at, responded_at)`.
  One row per unordered pair. Visible only to the two users. Only the
  addressee changes status. Sending a request to someone who already sent
  you one accepts theirs.
- `shared_entries(id, friendship_id, created_by, owed_by, owed_to, amount_minor > 0, currency char(3), entry_date, due_date, note, is_opening, status pending|accepted|rejected, version, created_at, updated_at, responded_at)`.
  Visible to `owed_by`/`owed_to` only, and only while they're accepted
  friends.

Writes that need column-level rules go through `security definer` RPCs,
never direct UPDATE: `find_user`, `send_friend_request`,
`respond_friend_request`, `add_entry`, `edit_entry`, `delete_entry`,
`respond_entry(id, accept, expected_version)`. A trigger blocks any change to
an accepted entry. Direction is stored absolutely (`owed_by`/`owed_to`);
each side derives "they owe / I owe" from its own user id.

Realtime is on for `friendships` and `shared_entries` (RLS-filtered).
Deleting an account cascades to its profile, friendships and entries.

## 2. Connector

- **Auth.** Login screen: Continue with GitHub / Continue with email
  (6-digit code). First login → pick-username screen (live availability
  check). Email users "Connect GitHub" later for backups via
  `linkIdentity`; the GitHub token is captured exactly as today.
- **Gate.** Signed in? → has username? → Home. Backup no longer blocks
  the app; it asks for GitHub + folder only inside its own tab.
- **Home tabs.** Friends (exact-username search, incoming / sent requests,
  friends with read-only net balance) and Backup (today's screens).
- **Local cache.** `shared.db` (SQLite): friends, entries, outbox.
- **ContentProvider** (Kotlin, `SharedDuesProvider`) over `shared.db`.
  Query friends/entries; `call` add/edit/delete/accept/reject/sync → outbox
  + `notifyChange`. Every call verifies the caller's package is
  `com.yash.xpenc` **and** its signing cert SHA-256 is allowlisted (Yash's
  key + F-Droid's XPENC key).
- **Sync engine** (Dart). Pushes the outbox via RPCs, pulls changes, holds
  a Realtime subscription. Runs in a headless FlutterEngine while XPENC
  holds a provider connection (which keeps Connector's process at XPENC's
  priority); stops shortly after XPENC disconnects. WorkManager runs it
  after any outbox write and every ~15 min. Only one engine runs at a time
  — two clients refreshing one Supabase session can invalidate it.

## 3. XPENC

- **Schema bump.** `Persons.remoteFriendId` (unique), `Persons.remoteUsername`;
  `PersonEntries.remoteEntryId` (unique), `sharedStatus`, `createdByMe`.
- **Counting.** Only accepted shared entries count toward person balances,
  reports and the Settled prompt. Pending ones show a badge. A local
  transaction (cash actually moved) still posts immediately as today.
- **Locked vs local fields.** Amount, date, direction, note are owned by
  the server. Account, category and mode stay local and editable.
- **UI.** Person detail → Link to Connector friend (offers the opening
  entry if the balance ≠ 0). Accept / Reject on incoming; "Waiting for
  @user" on outgoing; pending badge on the Persons tab. An entry from an
  unlinked friend prompts: link to existing person, or create one.
  Rejected entries: creator deletes or keeps as private local entry.
  Without Connector installed, all of it is hidden.
- **Merge.** Match on `remoteEntryId`; server wins for shared fields; a
  creator-deleted pending entry is removed; accepted entries are never
  removed by sync; unfriend clears the remote fields.
- **Bridge.** Kotlin MethodChannel/EventChannel over ContentResolver +
  ContentObserver, connection held only while XPENC is resumed.
  `<queries><package android:name="com.yash.xpenc.conectr"/></queries>`.
  XPENC verifies Connector's signing cert before sending anything.
- **Backups.** New columns go into exportAll/importAll; a restored device
  re-links by id on next sync.

## Errors

- Offline → outbox queues, XPENC shows "Not sent yet", retried next sync.
- Username race → unique constraint → "That username was just taken."
- Accepting an entry edited meanwhile → `expected_version` mismatch →
  "This entry changed — review it again."
- Session expired / GitHub token revoked → re-auth prompt.
- Connector uninstalled → XPENC hides sharing; entries keep their state.

## Testing

- SQL: RLS/RPC checks with two test users (can't read others' entries,
  can't accept own entry, can't edit accepted entry, etc.).
- Dart: username validation, merge rules, direction derivation, pending
  excluded from balances.
- XPENC: Drift migration test, backup round-trip keeps remote ids.
- Manual end-to-end on two phones with two accounts.

## Phases (each ships on its own)

1. Supabase `profiles` + Connector email login + username + GitHub as
   optional "Connect for backups".
2. Friends.
3. Shared entries + sync engine + ContentProvider (Connector debug screen
   to exercise it without XPENC).
4. XPENC side.

## Needed from Yash, per phase

- Phase 1: enable Email provider; custom SMTP (built-in mailer only
  reaches project team members); `{{ .Token }}` in both the "Magic Link"
  and "Confirm signup" templates (a first-time email sign-in can get
  either); enable Manual linking (Auth settings); paste the migration.
- Phase 3: a permanent release keystore for Connector (XPENC pins its
  cert); XPENC's signing certs (Yash's + F-Droid's).
- Ongoing: Supabase free tier pauses after ~1 week idle.
