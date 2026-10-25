import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/friends/friendship.dart';
import '../../core/providers.dart';
import 'friends_controller.dart';

/// What XPENC gets to see, so its Persons can be linked to friends: whether
/// someone is signed in, their username, and their accepted friends — no
/// requests, no ids beyond the friends' own. Version 1 of the shape XPENC
/// reads (`Money-Management/lib/core/connector/friends/
/// connector_friends_source.dart`).
Map<String, dynamic> friendsCachePayload({
  required bool signedIn,
  String? username,
  List<FriendLink> friends = const [],
  required DateTime now,
}) => {
  'version': 1,
  'signedIn': signedIn,
  'username': username,
  'updatedAt': now.millisecondsSinceEpoch,
  'friends': [
    for (final link in friends)
      {
        'id': link.other.id,
        'username': link.other.username,
        'display_name': link.other.displayName,
      },
  ],
};

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
