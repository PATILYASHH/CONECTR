import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/friends/friends_payload.dart';
import '../../core/friends/friendship.dart';
import '../../core/providers.dart';
import 'friends_controller.dart';

/// [friendsPayload] for the Friends tab's links.
Map<String, dynamic> friendsCachePayload({
  required bool signedIn,
  String? username,
  List<FriendLink> friends = const [],
  required DateTime now,
}) => friendsPayload(
  signedIn: signedIn,
  username: username,
  friends: [for (final link in friends) link.other],
  now: now,
);

/// The payload for the current account, or null while it's still loading —
/// publishing then would tell XPENC "signed out" for a moment on every
/// start. A friends list that failed to load keeps the last one shared.
final friendsCachePayloadProvider = Provider<Map<String, dynamic>?>((ref) {
  final authKnown = ref.watch(authStateProvider.select((s) => s.hasValue));
  if (!authKnown) return null;
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return friendsCachePayload(signedIn: false, now: DateTime.now());
  }
  final profile = ref.watch(myProfileProvider);
  if (!profile.hasValue) return null;
  final me = profile.value;
  if (me == null) {
    return friendsCachePayload(signedIn: true, now: DateTime.now());
  }
  final overview = ref.watch(friendsControllerProvider).value;
  if (overview == null) return null;
  return friendsCachePayload(
    signedIn: true,
    username: me.username,
    friends: overview.friends,
    now: DateTime.now(),
  );
});

/// Keeps the copy XPENC reads (Kotlin's `XpencProvider`, which answers
/// XPENC only) in step with the account and its friends, for as long as the
/// app runs. Called once from `main`.
void shareFriendsWithXpenc(ProviderContainer container) {
  const channel = MethodChannel('conectr/friends_cache');
  container.listen<Map<String, dynamic>?>(friendsCachePayloadProvider, (
    _,
    payload,
  ) {
    if (payload == null) return;
    channel
        .invokeMethod<void>('publish', jsonEncode(payload))
        .catchError((Object _) {});
  }, fireImmediately: true);
}
