import '../profile/profile_repository.dart';

enum FriendshipStatus { pending, accepted, declined }

/// One `friendships` row, with both people's profiles embedded.
class Friendship {
  const Friendship({
    required this.id,
    required this.status,
    required this.requester,
    required this.addressee,
    required this.createdAt,
    this.respondedAt,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) {
    Profile? profile(Object? row) =>
        row == null ? null : Profile.fromJson(row as Map<String, dynamic>);
    return Friendship(
      id: json['id'] as String,
      status: FriendshipStatus.values.byName(json['status'] as String),
      requester: profile(json['requester']),
      addressee: profile(json['addressee']),
      createdAt: DateTime.parse(json['created_at'] as String),
      respondedAt: json['responded_at'] == null
          ? null
          : DateTime.parse(json['responded_at'] as String),
    );
  }

  final String id;
  final FriendshipStatus status;

  /// Null only if RLS hid the profile — which the migration's profile
  /// policy shouldn't allow for either side of a row you can see.
  final Profile? requester;
  final Profile? addressee;

  final DateTime createdAt;
  final DateTime? respondedAt;
}

/// How someone is related to the signed-in user.
enum Relation {
  none,
  self,
  friend,

  /// They asked; waiting on you.
  incoming,

  /// You asked; waiting on them.
  outgoing,
}

/// A friendship row seen from one side: the other person and what they are
/// to you.
class FriendLink {
  const FriendLink({
    required this.friendshipId,
    required this.other,
    required this.relation,
    required this.since,
  });

  final String friendshipId;
  final Profile other;
  final Relation relation;

  /// When the request was sent, or — for friends — accepted.
  final DateTime since;
}

/// The Friends tab's three lists, from the signed-in user's side.
class FriendsOverview {
  const FriendsOverview({
    required this.myId,
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });

  factory FriendsOverview.from(List<Friendship> rows, String myId) {
    final friends = <FriendLink>[];
    final incoming = <FriendLink>[];
    final outgoing = <FriendLink>[];

    for (final row in rows) {
      final iAsked = row.requester?.id == myId;
      final other = iAsked ? row.addressee : row.requester;
      if (other == null) continue;

      final relation = switch (row.status) {
        FriendshipStatus.accepted => Relation.friend,
        FriendshipStatus.pending =>
          iAsked ? Relation.outgoing : Relation.incoming,
        // A quiet "no": the sender still sees "Requested", the person who
        // declined doesn't see it at all — until either asks again.
        FriendshipStatus.declined => iAsked ? Relation.outgoing : Relation.none,
      };
      final link = FriendLink(
        friendshipId: row.id,
        other: other,
        relation: relation,
        since: relation == Relation.friend
            ? row.respondedAt ?? row.createdAt
            : row.createdAt,
      );
      switch (relation) {
        case Relation.friend:
          friends.add(link);
        case Relation.incoming:
          incoming.add(link);
        case Relation.outgoing:
          outgoing.add(link);
        case Relation.none || Relation.self:
          break;
      }
    }

    friends.sort((a, b) => a.other.username.compareTo(b.other.username));
    int newestFirst(FriendLink a, FriendLink b) => b.since.compareTo(a.since);
    incoming.sort(newestFirst);
    outgoing.sort(newestFirst);

    return FriendsOverview(
      myId: myId,
      friends: friends,
      incoming: incoming,
      outgoing: outgoing,
    );
  }

  final String myId;
  final List<FriendLink> friends;
  final List<FriendLink> incoming;
  final List<FriendLink> outgoing;

  bool get isEmpty => friends.isEmpty && incoming.isEmpty && outgoing.isEmpty;

  /// The link with [userId], if any — for a search result's button.
  FriendLink? linkWith(String userId) {
    for (final link in [...friends, ...incoming, ...outgoing]) {
      if (link.other.id == userId) return link;
    }
    return null;
  }

  Relation relationTo(String userId) {
    if (userId == myId) return Relation.self;
    return linkWith(userId)?.relation ?? Relation.none;
  }
}
