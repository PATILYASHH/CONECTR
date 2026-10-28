# Google Drive backups & Google login — design

Status: approved 2026-10-28. Connector only; XPENC is untouched.

## Goal

Sign in to Connector with Google, and back XPENC up to a folder in your own
Google Drive as an alternative to the private GitHub repo. Every sync rule
that keeps one phone from overwriting another's backup holds for Drive
exactly as it does for GitHub.

## Decisions

| Question | Decision |
|---|---|
| Drive's role | Either/or with GitHub. One destination per account. |
| Where the choice lives | New `account_settings` table, self-only — account-wide, so two phones can't back up to different places. Not on `profiles`, which friends can read. Cached in SecureStore for the background job. |
| Google login vs Drive access | Separate steps. "Continue with Google" only signs in; Drive is connected from the Backup tab, by any account type. |
| Google auth mechanism | Native `google_sign_in` 7.x: ID token → `supabase.auth.signInWithIdToken`; Drive tokens from Play Services' AuthorizationClient, fetched silently whenever needed — background job included. No client secret in the app, no server. |
| Drive scope | `drive.file` (non-sensitive): Connector sees only the files it created. |
| Drive layout | Visible `XPENC Backup` folder in My Drive. One new file per upload (append-only), newest by server `createdTime` is "latest". |
| Drive conflict guard | No compare-and-swap in Drive v3, so: upload, then list backups created after the one this upload replaced; if any besides our own, delete ours and report a conflict. |
| Drive retention | Newest 30 backups kept; older ones permanently deleted after each successful upload. |
| Switching destination | Allowed from Settings, after a confirmation. Resets this phone's sync state; old backups stay where they are, unread. |
| Branch | `feature/google-drive`, cut from `feature/friends-shared-dues` (1.2.0 isn't on `main`). |

## 1. Components

```
Login screen ──► AuthService.signInWithGoogle() ──► GoogleAuth (google_sign_in)
                      └─ supabase.auth.signInWithIdToken(idToken, accessToken, nonce)

BackupSyncService (rules unchanged)
      │ uses
      ▼
BackupStore (interface)
  ├─ GithubBackupStore ──► GithubApi   (existing calls, moved out of the service)
  └─ DriveBackupStore  ──► DriveApi    (thin http wrapper, same style as GithubApi)
                              token: GoogleAuth.driveToken()
```

### GoogleAuth — `lib/core/google/google_auth.dart`

Owns everything Google. Initialised with `serverClientId` =
`GOOGLE_WEB_CLIENT_ID` (dart-define).

- `signIn()` → `authenticate()`, returns the ID token plus an access token
  for `openid email profile`. A random raw nonce is generated per sign-in;
  its SHA-256 goes to Google, the raw value to Supabase.
- `connectDrive()` → interactive `authorizeScopes([drive.file])`, hinted with
  the signed-in Google account when there is one. Stores the Google account
  email in SecureStore (`google_drive_email`).
- `driveToken()` → silent authorization for `drive.file` for the stored
  email, with `promptIfUnauthorized: false` — the account hint matters on
  phones with several Google accounts. The public `GoogleSignIn` API only
  hints with an authenticated user, so this goes through the platform
  interface (`clientAuthorizationTokensForScopes`; exact call confirmed in
  the step 0 spike). Returns null when the user must act; the caller turns
  that into "Reconnect Google Drive". Must work without an Activity, so
  the WorkManager job can call it — that's what the spike proves.
- `signOut()` → `GoogleSignIn.instance.signOut()`, so the next login shows
  the account picker.

### AuthService

Gains `signInWithGoogle()`. Drive access is not a Supabase identity — no
linking, nothing changes in Supabase when Drive is connected.

### BackupStore — `lib/core/backup/backup_store.dart`

```dart
abstract interface class BackupStore {
  /// Repo / folder exists. Called before an upload.
  Future<void> ensureReady();

  /// Newest backup, or null when there's none.
  Future<RemoteBackup?> latest();

  /// That exact version's bytes; null if it's gone.
  Future<List<int>?> download(RemoteBackup backup);

  /// Git blob sha of that version's content, without downloading it; null
  /// if unknown (then the upload simply goes ahead).
  Future<String?> contentShaOf(RemoteBackup backup);

  /// Stores [bytes] as the new latest, replacing [replacing] (null: there
  /// was none). Throws BackupConflictException if anything else became
  /// latest meanwhile. Returns the new version with the *server's* time
  /// (GitHub: the commit's committer date; Drive: `createdTime`) — today's
  /// code records the phone's `now`, which the §4 rule can't trust.
  Future<RemoteBackup> upload(
    List<int> bytes,
    BackupMeta meta, {
    required RemoteBackup? replacing,
  });
}
```

`BackupSyncService` takes a `BackupStore` instead of `GithubApi`;
`_context()` no longer resolves a GitHub owner — that moves into
`GithubBackupStore`. A factory picks the store from the cached destination,
used by both `backupSyncServiceProvider` and `autoSyncDispatcher`.

`GithubConflictException` becomes `BackupConflictException` (shared).

### Renames, with stored-state compatibility

- `RemoteBackup.commitSha` → `versionId` (GitHub: commit sha; Drive: file
  id). `fromJson` still reads `commitSha`.
- `SyncState.baseCommitSha` → `baseVersionId`,
  `lastPulledCommitSha` → `lastPulledVersionId`, same fallback.
- `NothingOnGithub` → `NothingRemote`.
- `XpencInbox`'s JSON keeps the key `commitSha` — that's XPENC's contract.

The XPENC handoff is unchanged: it's keyed on `gitBlobSha` of the file's
bytes, computed locally whatever the backend.

### Destination — `lib/core/backup/backup_destination.dart`

`enum BackupDestination { github, googleDrive }` with `label` ("GitHub",
"Google Drive"). Stored in `account_settings.backup_destination` (`github` |
`google_drive`; no row = not chosen) and mirrored to SecureStore
(`backup_destination`). An account with a stored GitHub token and no row
gets `github` written on first open — existing users see no change.

## 2. Supabase

New migration `20261028000001_account_settings.sql`, pasted into the SQL
Editor like the others. A table of its own rather than a `profiles`
column: phase 2 lets anyone with a friendship row — pending and declined
included — read your profile, and its migration promises nothing else is
in one.

```sql
create table public.account_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  backup_destination text not null
    constraint backup_destination_value
      check (backup_destination in ('github', 'google_drive')),
  updated_at timestamptz not null default now()
);

alter table public.account_settings enable row level security;

revoke all on public.account_settings from anon, authenticated;
grant select, insert, update (backup_destination, updated_at)
  on public.account_settings to authenticated;

create policy "Users read their own settings"
  on public.account_settings for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users create their own settings"
  on public.account_settings for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users update their own settings"
  on public.account_settings for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
```

`AccountSettingsRepository` (`lib/core/profile/`): `fetchBackupDestination()`
and `setBackupDestination()` (upsert).

## 3. Drive storage — `DriveBackupStore`

- **Folder.** Created as `XPENC Backup` in My Drive root with
  `appProperties: {connector: backupFolder}`. Found by that tag
  (`trashed = false`), oldest first — rename or move it freely. Trashed →
  the next upload creates a new one. Its id is cached in SecureStore and
  re-looked-up on 404.
- **Files.** One per upload, named `XPENC <yyyy-MM-dd HH.mm> — <device>.json`
  (local time, for humans only). `appProperties`:
  `connector=backup`, `deviceId`, `deviceName`, `backupModified`,
  `sourceFile`, `contentSha` (git blob sha). Each key+value stays under
  Drive's 124-byte limit (device names are capped at 40 chars).
  Uploaded with a resumable upload (metadata and content in one session —
  no 5 MB multipart cap, and the file never exists without its metadata).
- **Latest.** `files.list` with `appProperties has {key='connector' and
  value='backup'} and trashed = false`, `orderBy=createdTime desc`,
  `pageSize=1`. Found by tag, not by folder, so a duplicate folder from two
  phones racing to create it doesn't matter. `RemoteBackup.committedAt` =
  `createdTime` (server time). A file without readable metadata becomes a
  `RemoteBackup` with `meta: null`, as an old-style GitHub commit does.
- **Conflict guard.** After creating file F, list tagged backups with
  `createdTime > replacing.committedAt` (all of them when `replacing` is
  null). Anything other than F → delete F, throw `BackupConflictException`.
  If two phones upload at once, both back off; the next run settles it.
  If deleting F itself fails, that error is thrown instead (not transient),
  so the user sees it rather than F quietly standing as latest.
- **Retention.** After a successful upload, tagged backups beyond the newest
  30 are deleted (`files.delete`, permanent — trash would still count
  against quota).
- **Download.** `files.get?alt=media` by file id; 404 → null → `NothingRemote`.

### DriveApi — `lib/core/google/drive_api.dart`

Stateless, token passed per call like `GithubApi`: `findFolder`,
`createFolder`, `listBackups({createdAfter, pageSize})`, `upload`
(resumable: initiate + PUT), `download`, `delete`. Errors →
`DriveApiException(statusCode, reason, message)`, `reason` taken from
Google's error body (`storageQuotaExceeded`, `rateLimitExceeded`, …).

## 4. Shared sync rule fix: hand-deleted backups

Delete the newest backup in Drive (or force-push on GitHub) and an older one
becomes "latest". Today's `isFromElsewhere` would call it new data from
another phone; the phone pulls it, and XPENC — whose "no local changes"
check passes — could take the older data in by itself. Data loss.

Fix: `SyncState.baseCommittedAt`, the server time of the version this phone
is built on, set wherever `baseVersionId` is set (upload — from the server
time `BackupStore.upload` returns —, identical-content match, confirmed
import). Existing state has no value, so the rule only kicks in after the
next upload or import. `isFromElsewhere` returns false when
`baseCommittedAt != null && !remote.committedAt.isAfter(baseCommittedAt)`.
Server times only — the rule that phones' clocks are never compared stands.
Effect: the phone ignores the older backup and its next upload becomes
latest again.

## 5. Screens and flows

- **Login.** "Continue with Google" (filled, first), then GitHub and email
  (outlined). Intro copy: "…backs up its data to your own Google Drive or
  private GitHub repo…". Username screen afterwards unchanged.
- **BackupGate.** destination chosen? → connected? → folder chosen? →
  dashboard.
  - **ChooseDestinationScreen** (new): two cards, *Google Drive* ("A
    folder in your Drive you can see") and *GitHub* ("A private repo").
    Picking saves to `account_settings` and the cache.
  - A phone whose account already has a destination skips straight to
    connecting it.
  - **ConnectDriveScreen** (new): "Connect Google Drive" → account picker →
    Google consent. One consent for a Google-signed-in account.
  - **ConnectGithubScreen**: unchanged.
- **Dashboard, controller, notifications, dialogs.** Every "GitHub" in
  user-facing text uses `destination.label`. The overwrite dialog's last
  sentence becomes destination-specific: GitHub "stays in the repo's
  history"; Drive "stays in the XPENC Backup folder".
- **Settings → Backup.**
  - Destination row: *Google Drive · you@gmail.com* (opens the folder at
    `https://drive.google.com/drive/folders/<id>`), or today's GitHub row.
  - **Change destination** → confirm: "Backups from all your phones go to
    <new> from now on. Your <old> backups stay where they are, but
    Connector stops reading them." Then: write `account_settings` + cache, reset
    `SyncState` (keeping nothing — old version ids mean nothing on the new
    backend), forget the old destination's token on this phone, and the
    gate asks to connect the new one.
- **Other phones after a switch** pick it up the next time Connector is
  opened on them (`account_settings` differs from the cache → same reset). Until
  then their background job keeps using the old destination — harmless,
  but their new data doesn't reach the new one. Known limitation; listed
  under "Not yet built" in the README.
- **Sign out** also calls `GoogleAuth.signOut()`; the dialog says it
  forgets "the backup connection" rather than naming GitHub.

## 6. Errors — `SyncFailure.from`

| Error | Message | Flags |
|---|---|---|
| `BackupConflictException` | "The backup on <dest> changed while uploading. Sync again." | transient |
| `driveToken()` null, or `DriveApiException` 401 | "Google Drive access was revoked or has expired. Reconnect Google Drive." | needsReconnect |
| `DriveApiException` reason `storageQuotaExceeded` | "Your Google Drive is full." | — |
| `DriveApiException` 429, or reason `rateLimitExceeded` / `userRateLimitExceeded` | "Google Drive is rate-limiting requests." | transient |
| `DriveApiException` ≥ 500 | "Google Drive is having trouble." | transient |
| Network errors | "Couldn't reach <dest>. Check your connection." | transient |

`problemNeedsReconnect`'s button calls `connectGithub()` or
`GoogleAuth.connectDrive()` by destination. No Play Services (some custom
ROMs): the Google login button and Connect Drive show the plugin's error as
text; GitHub and email still work.

## 7. Testing

Unit:
- `sync_rules_test`: `baseCommittedAt` — an older remote is never "from
  elsewhere"; equal time with a different version id isn't either; a newer
  one from another phone still is.
- `drive_backup_store_test` (fake `DriveApi`): latest by tag across two
  folders; conflict guard deletes our file and throws; both-phones race;
  retention keeps exactly 30 and never the new upload; a file without
  `appProperties` → `meta: null`; `contentShaOf` reads `appProperties`.
- `backup_sync_service_test`: moves from a fake GitHub to a fake
  `BackupStore`; existing cases keep passing unchanged in meaning.
- `sync_state` / `backup_meta`: old JSON with `commitSha` keys loads;
  `BackupMeta` ↔ `appProperties` round-trips.

On device (manual): Google login; connect Drive; upload on phone 1; pull
on phone 2 and XPENC takes it in; delete the newest Drive backup by hand →
no pull of the older one; switch destination both ways.

## 8. One-time setup (goes into the README)

1. Google Cloud project → enable **Google Drive API**.
2. OAuth consent screen: External; scopes `openid`, `email`, `profile`,
   `drive.file`; **publish to Production**. In "Testing" Google expires
   grants after 7 days and auto-sync would break weekly. All four scopes
   are non-sensitive — no Google review.
3. OAuth client, type **Android**: package `com.yash.xpenc.conectr`, SHA-1
   from `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore
   -alias androiddebugkey -storepass android`. A real release keystore later
   needs a second Android client with its SHA-1.
4. OAuth client, type **Web**: its Client ID → `GOOGLE_WEB_CLIENT_ID` in
   `dart_define.local.json` (and the example file); Client ID + secret →
   Supabase → Authentication → Providers → Google (enable it).
5. Paste `supabase/migrations/20261028000001_account_settings.sql` into
   the SQL Editor.

`AppConfig` gains `googleWebClientId`; a missing value disables the Google
buttons with a "not configured" note instead of crashing.

## 9. Build order

Each step leaves the app working.

0. **Spike — go/no-go.** Throwaway code: connect Drive in the app, then
   fetch a token silently inside a WorkManager run and list files. If Play
   Services refuses without an Activity, stop and revisit (fallback:
   approach B, a Supabase Edge Function refreshing tokens) before anything
   else is built.
1. `BackupStore` + `GithubBackupStore`, renames with JSON fallback,
   `baseCommittedAt` rule, shared conflict exception. GitHub behaviour
   identical; tests green.
2. Google login (`GoogleAuth`, `AuthService.signInWithGoogle`, login
   screen, `AppConfig`).
3. Migration, `BackupDestination`, `DriveApi`, `DriveBackupStore`,
   ChooseDestination / ConnectDrive screens, gate, store factory, error
   mapping.
4. Settings (destination row, change destination), destination-neutral
   text everywhere, README setup + "Not yet built", version 1.3.0.

## Out of scope

- Mirroring to both destinations.
- Copying existing backups across when switching.
- Linking a Google identity to an existing Supabase account.
- Telling a closed phone's background job about a destination switch.
- Encryption before upload — still open from the README, for both backends.
