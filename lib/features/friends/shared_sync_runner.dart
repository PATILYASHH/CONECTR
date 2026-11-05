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

/// Net of the accepted entries with each friend, per currency, from this
/// account's side: `+` they owe you, `-` you owe them. Read-only here —
/// entries are made and answered in XPENC.
final sharedBalancesProvider = FutureProvider<Map<String, Map<String, int>>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final snapshot = await SharedFiles().readSnapshot();
  final entries = snapshot?['entries'];
  if (snapshot?['signedIn'] != true || entries is! List) return const {};
  final net = <String, Map<String, int>>{};
  for (final e in entries.cast<Map<String, dynamic>>()) {
    if (e['status'] != 'accepted') continue;
    final amount = (e['amountMinor'] as num).toInt();
    final byCurrency = net.putIfAbsent(e['friendId'] as String, () => {});
    final currency = e['currency'] as String;
    byCurrency[currency] =
        (byCurrency[currency] ?? 0) + (e['theyOwe'] == true ? amount : -amount);
  }
  return net;
});

/// "Owes you ₹500", "You owe $12.50", or null when they're square.
String? balanceLabel(Map<String, int>? byCurrency) {
  final parts = [
    for (final MapEntry(key: currency, value: minor)
        in (byCurrency ?? const <String, int>{}).entries)
      if (minor != 0)
        '${minor > 0 ? 'Owes you' : 'You owe'} ${_money(minor.abs(), currency)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _money(int minor, String currency) {
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
        _ref.invalidate(sharedBalancesProvider);
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
