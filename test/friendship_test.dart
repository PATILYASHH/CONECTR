import 'package:conectr/core/friends/friendship.dart';
import 'package:conectr/core/profile/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const me = Profile(id: 'me', username: 'yash');
const ana = Profile(id: 'a', username: 'ana');
const ben = Profile(id: 'b', username: 'ben');
const cat = Profile(id: 'c', username: 'cat');

Friendship row(
  String id,
  Profile from,
  Profile to,
  FriendshipStatus status, {
  int day = 1,
}) {
  return Friendship(
    id: id,
    status: status,
    requester: from,
    addressee: to,
    createdAt: DateTime.utc(2026, 10, day),
    respondedAt: status == FriendshipStatus.pending
        ? null
        : DateTime.utc(2026, 10, day + 1),
  );
}

void main() {
  test('accepted rows are friends, whoever asked', () {
    final o = FriendsOverview.from([
      row('1', me, ben, FriendshipStatus.accepted),
      row('2', ana, me, FriendshipStatus.accepted),
    ], 'me');
    expect(o.friends.map((l) => l.other.username), ['ana', 'ben']);
    expect(o.incoming, isEmpty);
    expect(o.outgoing, isEmpty);
  });

  test('pending splits into incoming and outgoing', () {
    final o = FriendsOverview.from([
      row('1', ana, me, FriendshipStatus.pending),
      row('2', me, ben, FriendshipStatus.pending),
    ], 'me');
    expect(o.incoming.single.other, ana);
    expect(o.outgoing.single.other, ben);
    expect(o.relationTo('a'), Relation.incoming);
    expect(o.relationTo('b'), Relation.outgoing);
  });

  test('a declined request still looks pending to its sender only', () {
    final sent = FriendsOverview.from([
      row('1', me, ana, FriendshipStatus.declined),
    ], 'me');
    expect(sent.outgoing.single.other, ana);

    final received = FriendsOverview.from([
      row('1', ana, me, FriendshipStatus.declined),
    ], 'me');
    expect(received.isEmpty, isTrue);
    expect(received.relationTo('a'), Relation.none);
  });

  test('friends since is when it was accepted', () {
    final o = FriendsOverview.from([
      row('1', me, ana, FriendshipStatus.accepted, day: 5),
    ], 'me');
    expect(o.friends.single.since, DateTime.utc(2026, 10, 6));
  });

  test('requests are newest first', () {
    final o = FriendsOverview.from([
      row('1', ana, me, FriendshipStatus.pending, day: 1),
      row('2', cat, me, FriendshipStatus.pending, day: 9),
      row('3', ben, me, FriendshipStatus.pending, day: 4),
    ], 'me');
    expect(o.incoming.map((l) => l.other.username), ['cat', 'ben', 'ana']);
  });

  test('relation to yourself and to strangers', () {
    final o = FriendsOverview.from([], 'me');
    expect(o.relationTo('me'), Relation.self);
    expect(o.relationTo('zed'), Relation.none);
  });

  test('rows with a hidden profile are skipped', () {
    final o = FriendsOverview.from([
      Friendship(
        id: '1',
        status: FriendshipStatus.accepted,
        requester: me,
        addressee: null,
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    ], 'me');
    expect(o.isEmpty, isTrue);
  });

  test('parses a PostgREST row with embedded profiles', () {
    final f = Friendship.fromJson({
      'id': 'f1',
      'status': 'pending',
      'created_at': '2026-10-24T09:40:00+00:00',
      'responded_at': null,
      'requester': {'id': 'a', 'username': 'ana', 'display_name': null},
      'addressee': {'id': 'me', 'username': 'yash', 'display_name': 'Yash'},
    });
    expect(f.status, FriendshipStatus.pending);
    expect(f.requester!.username, 'ana');
    expect(f.addressee!.displayName, 'Yash');
    expect(f.createdAt, DateTime.utc(2026, 10, 24, 9, 40));
  });
}
