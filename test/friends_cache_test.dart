import 'package:conectr/core/friends/friendship.dart';
import 'package:conectr/core/profile/profile_repository.dart';
import 'package:conectr/features/friends/friends_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);

  test('shares accepted friends in the shape XPENC reads', () {
    final payload = friendsCachePayload(
      signedIn: true,
      username: 'yash',
      friends: [
        FriendLink(
          friendshipId: 'f1',
          other: const Profile(
            id: 'u-ana',
            username: 'ana',
            displayName: 'Ana',
          ),
          relation: Relation.friend,
          since: now,
        ),
      ],
      now: now,
    );
    expect(payload, {
      'version': 1,
      'signedIn': true,
      'username': 'yash',
      'updatedAt': now.millisecondsSinceEpoch,
      'friends': [
        {'id': 'u-ana', 'username': 'ana', 'display_name': 'Ana'},
      ],
    });
  });

  test('signed out shares nothing but that', () {
    final payload = friendsCachePayload(signedIn: false, now: now);
    expect(payload['signedIn'], isFalse);
    expect(payload['username'], isNull);
    expect(payload['friends'], isEmpty);
  });
}
