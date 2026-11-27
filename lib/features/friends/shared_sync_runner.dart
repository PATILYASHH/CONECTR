import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/background/auto_sync.dart';
import '../../core/notifications/app_notifications.dart';
import '../../core/providers.dart';
import '../../core/shared/shared_files.dart';
import '../../core/shared/shared_sync.dart';
import 'friends_controller.dart';

/// One entry with a friend, from this account's side, as the last sync
/// left it in `shared.json`. Read-only here — entries are made and answered
/// in XPENC.
class FriendEntry {
  const FriendEntry({
    required this.byMe,
    required this.theyOwe,
    required this.amountMinor,
    required this.currency,
    required this.date,
    this.note,
    this.isOpening = false,
    required this.status,
    required this.updatedAt,
  });

  final bool byMe;
  final bool theyOwe;
  final int amountMinor;
  final String currency;

  /// `yyyy-mm-dd`.
  final String date;
  final String? note;
  final bool isOpening;

  /// `pending`, `accepted` or `rejected`.
  final String status;
  final String updatedAt;

  bool get toAnswer => !byMe && status == 'pending';
  bool get waitingOnThem => byMe && status == 'pending';
}

/// The entries in a `shared.json` snapshot, per friend, newest first.
/// Empty when it's signed out or was written for another account.
Map<String, List<FriendEntry>> entriesByFriend(
  Map<String, dynamic>? snapshot,
  String? myId,
) {
  final entries = snapshot?['entries'];
  if (myId == null ||
      snapshot?['signedIn'] != true ||
      snapshot?['me'] != myId ||
      entries is! List) {
    return const {};
  }
  final byFriend = <String, List<FriendEntry>>{};
  for (final e in entries.whereType<Map<String, dynamic>>()) {
    try {
      byFriend
          .putIfAbsent(e['friendId'] as String, () => [])
          .add(
            FriendEntry(
              byMe: e['byMe'] == true,
              theyOwe: e['theyOwe'] == true,
              amountMinor: (e['amountMinor'] as num).toInt(),
              currency: e['currency'] as String,
              date: e['date'] as String,
              note: e['note'] as String?,
              isOpening: e['isOpening'] == true,
              status: e['status'] as String,
              updatedAt: e['updatedAt'] as String? ?? '',
            ),
          );
    } on TypeError {
      // A row this version can't read; the rest still shows.
    }
  }
  for (final list in byFriend.values) {
    list.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.updatedAt.compareTo(a.updatedAt);
    });
  }
  return byFriend;
}

/// Net of the accepted entries, per currency: `+` they owe you, `-` you
/// owe them.
Map<String, int> netOf(Iterable<FriendEntry> entries) {
  final net = <String, int>{};
  for (final e in entries) {
    if (e.status != 'accepted') continue;
    net[e.currency] =
        (net[e.currency] ?? 0) + (e.theyOwe ? e.amountMinor : -e.amountMinor);
  }
  return net;
}

final sharedEntriesProvider = FutureProvider<Map<String, List<FriendEntry>>>((
  ref,
) async {
  final myId = ref.watch(currentUserIdProvider);
  return entriesByFriend(await SharedFiles().readSnapshot(), myId);
});

/// [netOf] each friend's entries, by friend id.
final sharedBalancesProvider = FutureProvider<Map<String, Map<String, int>>>((
  ref,
) async {
  final byFriend = await ref.watch(sharedEntriesProvider.future);
  return {
    for (final MapEntry(:key, :value) in byFriend.entries) key: netOf(value),
  };
});

/// "Owes you ₹500", "You owe $12.50", or null when they're square.
String? balanceLabel(Map<String, int>? byCurrency) {
  final parts = [
    for (final MapEntry(key: currency, value: minor)
        in (byCurrency ?? const <String, int>{}).entries)
      if (minor != 0)
        '${minor > 0 ? 'Owes you' : 'You owe'} ${moneyLabel(minor.abs(), currency)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String moneyLabel(int minor, String currency) {
  try {
    return NumberFormat.simpleCurrency(name: currency).format(minor / 100);
  } catch (_) {
    return '$currency ${(minor / 100).toStringAsFixed(2)}';
  }
}

/// Runs [SharedSync] from the app for as long as someone is signed in: on
/// start, on coming back to the foreground, whenever the friends list
/// changes, and live on any change to this account's shared entries
/// (Realtime). Keeps the background job scheduled while there are friends
/// — which is what carries entries between XPENC and Supabase while
/// Connector is closed.
class SharedSyncRunner {
  SharedSyncRunner(this._ref);

  final Ref _ref;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _disposed = false;

  void start(String userId) {
    final client = Supabase.instance.client;
    _channel = client
        .channel('shared_entries:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shared_entries',
          callback: (_) => kick(),
        )
        .subscribe((status, _) {
          // Also catches up on whatever was missed while disconnected.
          if (status == RealtimeSubscribeStatus.subscribed) kick();
        });
  }

  /// Soon, once — a burst of changes is one round.
  void kick() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final outcome = await SharedSync(
        announce: AppNotifications.sharedEntry,
      ).run(wait: const Duration(seconds: 20));
      if (_disposed) return;
      if (outcome == SharedSyncOutcome.synced) {
        _ref.invalidate(sharedEntriesProvider);
      }
    });
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
  }
}

/// Watched by the home shell, so it lives as long as a signed-in session.
final sharedSyncRunnerProvider = Provider<SharedSyncRunner?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final runner = SharedSyncRunner(ref);
  ref.onDispose(runner.dispose);
  runner.start(userId);

  // A new or removed friend changes what XPENC may link — and whether the
  // background job is worth running at all.
  ref.listen<int?>(
    friendsControllerProvider.select((f) => f.value?.friends.length),
    (_, count) {
      if (count == null) return;
      SharedSyncScheduler.apply(active: count > 0).ignore();
      runner.kick();
    },
    fireImmediately: true,
  );
  return runner;
});
