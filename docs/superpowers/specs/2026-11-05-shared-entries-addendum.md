# Shared entries (phases 3–4) — as built

Addendum to `2026-10-24-friends-shared-dues-design.md`. Status: built
2026-11-05, awaiting the migration and a two-phone test.

## What it does

A person in XPENC linked to a Connector friend can have entries shared with
that friend. The friend accepts or rejects each one in their own XPENC; an
accepted entry is recorded on their person for you, the other way round, and
can never change again (fix it with a correcting entry).

## Changes from the October spec

| Spec said | Built | Why |
|---|---|---|
| `shared.db` (SQLite) + `SharedDuesProvider` + headless engine while XPENC holds a connection | Files in `filesDir/xpenc/` (`outbox/`, `shared.json`, `friends.json`) behind the existing `XpencProvider`; a WorkManager one-off run per queued op, plus every 15 min while there are friends | Same pattern as the backup inbox, which already works. One provider, one cert check. WorkManager already starts a headless engine. |
| Only accepted entries count, on both sides | The **receiver's** side counts only after accepting. The **creator's** entry counts on their side at once, with "Waiting for @x" / "Rejected by @x" on it | XPENC reads person entries for balances in ~30 places (persons, trips, groups, reports). The creator's own record is theirs anyway, and a lend that moved money already posts at once (as the spec allowed). Switching to the spec's rule is a contained change if wanted. |
| Rejected: creator deletes or keeps it private | Also: edit and save, which proposes it again | Fixing a typo shouldn't mean starting over. |
| Opening entry, "accepted like any other" | On accepting, the receiver gets the *difference* from the balance they already had, so both sides end on the agreed number. Their earlier history is untouched | Otherwise an existing private balance would be counted twice. |
| — | XPENC web: hidden for now | Its built-in Connector would need the same flows over REST. |

## Moving parts

- **Supabase:** `supabase/migrations/20261105000001_shared_entries.sql` —
  `shared_entries` with RLS, a trigger locking accepted rows, and four RPCs.
  `client_ref` makes a retried add idempotent; answers name the `version`
  they saw.
- **Connector:** `lib/core/shared/` — `SessionTokens` (exactly one party
  refreshes the Supabase session: the app while it runs, else the
  background job under a lock), `SharedApi` (REST), `SharedFiles`,
  `SharedSync` (send the outbox in order, stop at the first retryable
  failure, then read everything). The app also syncs on open, on resume and
  live over Realtime. Friends' new entries are announced by notification;
  tapping it opens XPENC.
- **XPENC:** four columns on `PersonEntries` (`sharedRef`, `remoteEntryId`,
  `sharedStatus`, `sharedAccount`), `lib/core/connector/shared/`
  (`planSharedMerge` is pure and tested), `features/persons/shared_entries.dart`
  (the controller, the card on a person, the "Shared with you" card on
  Persons).

## Needed before it works

1. Paste the migration into the Supabase SQL editor.
2. Both phones: install both apps, sign in to Connector, become friends,
   link the person in XPENC.
3. XPENC's `database.g.dart` was patched by hand for the four columns
   (build_runner on Dart 3.13 beta finds no database class here — even
   for HEAD). Regenerate on a working toolchain; the output should match.
