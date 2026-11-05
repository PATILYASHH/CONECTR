import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../backup/sync_lock.dart';
import '../friends/friends_payload.dart';
import 'session_tokens.dart';
import 'shared_api.dart';
import 'shared_entry.dart';
import 'shared_files.dart';

/// An incoming entry worth telling the user about: new, or changed since.
typedef AnnounceEntry =
    Future<void> Function(SharedEntry entry, String? fromUsername);

/// What one round came to — for the app's own screens and tests.
enum SharedSyncOutcome {
  synced,

  /// Pushed nothing and read nothing: offline, or the session is refused.
  unavailable,
  signedOut,

  /// Another round (the app's or the background job's) was already on it.
  busy,
}

/// One round between XPENC's shared-entry requests and Supabase, the same
/// in the app and in the background job:
///
/// 1. send what XPENC queued (`outbox/`), oldest first — stopping at the
///    first op that may work later, so an edit never overtakes its add;
/// 2. read every entry and friend this account can see;
/// 3. leave them for XPENC (`shared.json`, `friends.json` — the provider
///    tells XPENC they changed), and announce new incoming entries.
///
/// Ops the server refuses for good (not friends any more, accepted
/// meanwhile) are set aside with the reason, for XPENC to show.
class SharedSync {
  SharedSync({
    SharedApi? api,
    SharedFiles? files,
    Future<TokenResult> Function()? tokens,
    this.announce,
    DateTime Function()? now,
  }) : _api = api ?? SharedApi(),
       _files = files ?? SharedFiles(),
       _tokens = tokens ?? SessionTokens.get,
       _now = now ?? DateTime.now;

  final SharedApi _api;
  final SharedFiles _files;
  final Future<TokenResult> Function() _tokens;
  final AnnounceEntry? announce;
  final DateTime Function() _now;

  /// [wait]: how long to wait for a round already running — the app waits
  /// a little so its screens show the result; the background job doesn't.
  Future<SharedSyncOutcome> run({Duration wait = Duration.zero}) async {
    try {
      return await SyncLock.run(_run, lock: SyncLock.sharedName, wait: wait);
    } on SyncBusyException {
      return SharedSyncOutcome.busy;
    }
  }

  Future<SharedSyncOutcome> _run() async {
    var token = await _tokens();
    if (token is SignedOut) {
      await _files.dropOutbox('signed_out');
      await _files.writeSnapshot(signedIn: false, now: _now());
      return SharedSyncOutcome.signedOut;
    }
    if (token is! HaveToken) return SharedSyncOutcome.unavailable;

    try {
      try {
        await _push(token);
      } on SessionRefusedException {
        // Expired between asking and using it: one fresh token, once.
        token = await _tokens();
        if (token is! HaveToken) return SharedSyncOutcome.unavailable;
        await _push(token);
      }
      await _pull(token);
      return SharedSyncOutcome.synced;
    } on SessionRefusedException {
      return SharedSyncOutcome.unavailable;
    } on SocketException {
      return SharedSyncOutcome.unavailable;
    } on http.ClientException {
      return SharedSyncOutcome.unavailable;
    } on TimeoutException {
      return SharedSyncOutcome.unavailable;
    } on SharedApiException {
      // A read that failed (Supabase down, paused project): try next round.
      return SharedSyncOutcome.unavailable;
    }
  }

  Future<void> _push(HaveToken token) async {
    for (final queued in await _files.outbox()) {
      final op = queued.op;
      if (op == null) {
        await _files.fail(queued, 'unreadable');
        continue;
      }
      try {
        await _api.apply(token.accessToken, op);
        await _files.done(queued);
      } on SharedApiException catch (e) {
        if (!e.permanent) rethrow;
        await _files.fail(queued, _code(e.message));
      }
    }
  }

  Future<void> _pull(HaveToken token) async {
    final entries = await _api.fetchEntries(token.accessToken);
    final friends = await _api.fetchFriends(token.accessToken, token.userId);
    final now = _now();
    await _files.writeSnapshot(
      signedIn: true,
      myId: token.userId,
      username: friends.username,
      entries: entries,
      now: now,
    );
    await _files.writeFriends(
      friendsPayload(
        signedIn: true,
        username: friends.username,
        friends: friends.friends,
        now: now,
      ),
    );
    await _announceNew(entries, token.userId, {
      for (final f in friends.friends) f.id: f.username,
    });
  }

  /// Once per incoming pending entry and version — a friend's edit is news
  /// again; the next round's look at the same entry isn't.
  Future<void> _announceNew(
    List<SharedEntry> entries,
    String myId,
    Map<String, String> usernames,
  ) async {
    final seen = await _files.seen();
    final waiting = {
      for (final e in entries)
        if (e.createdBy != myId && e.status == 'pending') e.id: e,
    };
    var changed = false;
    for (final entry in waiting.values) {
      if (seen[entry.id] == entry.version) continue;
      seen[entry.id] = entry.version;
      changed = true;
      try {
        await announce?.call(entry, usernames[entry.createdBy]);
      } catch (_) {
        // A notification that can't show mustn't fail the sync.
      }
    }
    // Answered or withdrawn ones needn't be remembered.
    final before = seen.length;
    seen.removeWhere((id, _) => !waiting.containsKey(id));
    if (changed || seen.length != before) await _files.saveSeen(seen);
  }

  /// The functions' own refusals carry just their code; anything else is
  /// summed up by the first word or so.
  static String _code(String message) {
    const known = {
      'not_friends',
      'entry_locked',
      'entry_changed',
      'entry_not_found',
      'entry_not_pending',
      'not_signed_in',
    };
    for (final code in known) {
      if (message.contains(code)) return code;
    }
    return 'refused';
  }
}
