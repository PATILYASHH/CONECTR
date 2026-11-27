# Addendum: three backup destinations — GitHub, Google Drive, ExoCloud

Status: approved 2026-11-27. Extends
[2026-10-28-google-drive-and-login-design.md](2026-10-28-google-drive-and-login-design.md);
everything there holds unless changed here.

## Decisions

| Question | Decision |
|---|---|
| Destinations | Three, either/or per account: `github`, `google_drive`, `exocloud`. The chooser shows Drive first ("easiest"), ExoCloud, then GitHub ("for developers"). |
| ExoCloud storage | Supabase Storage bucket `exocloud` (private, 10 MB, `application/octet-stream`), one folder per user (`<uid>/…`), at most 20 objects per user. |
| ExoCloud privacy | End-to-end encrypted on the phone (AES-256-GCM). Random 32-byte key per account, on the user's phones only; shown once as a 52-character Crockford base32 **recovery key**. `account_settings.exocloud_key_check` (HMAC of a fixed label) lets a new phone verify a typed key. |
| ExoCloud plan | Free during beta; newest **10** backups kept. A paid tier raises the caps later. |
| ExoCloud conflict guard | True compare-and-swap: upload the object, then `exocloud_commit(p_replacing)` refuses (`exocloud_conflict`) unless the latest row is still the one replaced; the loser deletes its object. Server `created_at` is "newest". |
| Google login | Included, as in the base spec. |

## What changed from the base spec

- `BackupStore` gained `destination`, `isConnected()`, `guard()` (GitHub's
  401 double-check moved there; Drive retries a 401 once with a fresh token)
  and `accessWorks()` (for clearing a recorded "Reconnect").
- `account_settings` also holds `exocloud_key_check`; its migration is
  `20261127000001_backup_destinations.sql`, which also creates the bucket,
  `exocloud_backups` and `exocloud_commit`.
- `upsert` isn't used on `account_settings`: the update grant leaves out
  `user_id`, so the repository updates, then inserts.
- The background job reads the destination from SecureStore
  (`cachedDestination`); a pre-1.4 account with a GitHub token is GitHub.
- ExoCloud uses REST + `SessionTokens` like shared entries, so it works
  without a Supabase client in the background job.

## Testing

Unit: `exocloud_test` (crypto round-trip, tamper, recovery key parsing,
store commit/conflict/retention against a fake), `drive_backup_store_test`
(latest by tag, conflict guard, race, retention, trashed folder, revoked
access), `sync_rules_test` (`baseCommittedAt`), `backup_meta_test`
(pre-1.4 JSON).

On device (manual, still to do): Google login; Drive connect, upload,
pull on a second phone, background sync with the app closed (the spike
from the base spec); ExoCloud set-up on phone 1, recovery key on phone 2;
switching destination both ways; an existing GitHub user upgrading.
