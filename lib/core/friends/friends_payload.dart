import '../profile/profile_repository.dart';

/// What XPENC gets to see, so its Persons can be linked to friends: whether
/// someone is signed in, their username, and their accepted friends — no
/// requests, no ids beyond the friends' own. Version 1 of the shape XPENC
/// reads (`XPENC/lib/core/connector/friends/
/// connector_friends_source.dart`). Built by the app as the list changes
/// (`friends_cache.dart`) and by the background sync (`SharedSync`).
Map<String, dynamic> friendsPayload({
  required bool signedIn,
  String? username,
  List<Profile> friends = const [],
  required DateTime now,
}) => {
  'version': 1,
  'signedIn': signedIn,
  'username': username,
  'updatedAt': now.millisecondsSinceEpoch,
  'friends': [
    for (final friend in friends)
      {
        'id': friend.id,
        'username': friend.username,
        'display_name': friend.displayName,
      },
  ],
};
