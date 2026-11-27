import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/profile_repository.dart';
import 'friendship.dart';

/// The request was cancelled by its sender (or already answered) before
/// this phone's answer arrived.
class FriendRequestGoneException implements Exception {}

/// The `friendships` table and its RPCs (see
/// `supabase/migrations/20261024000002_friends.sql`). RLS limits every read
/// to rows the signed-in user is part of; the RPCs hold the rules for
/// creating and answering requests.
class FriendsRepository {
  static const _select =
      'id, status, created_at, responded_at, '
      'requester:profiles!friendships_requester_id_fkey(id, username, display_name), '
      'addressee:profiles!friendships_addressee_id_fkey(id, username, display_name)';

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Friendship>> fetchAll() async {
    final rows = await _client.from('friendships').select(_select);
    return [for (final row in rows) Friendship.fromJson(row)];
  }

  /// Exact match on an already-normalized username, or null.
  Future<Profile?> findUser(String username) async {
    final rows =
        await _client.rpc('find_user', params: {'p_username': username})
            as List<dynamic>;
    return rows.isEmpty
        ? null
        : Profile.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Also accepts their request instead, if they'd already sent one.
  Future<void> sendRequest(String userId) async {
    await _client.rpc(
      'send_friend_request',
      params: {'p_addressee_id': userId},
    );
  }

  Future<void> respond(String friendshipId, {required bool accept}) async {
    try {
      await _client.rpc(
        'respond_friend_request',
        params: {'p_friendship_id': friendshipId, 'p_accept': accept},
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('request_not_found')) {
        throw FriendRequestGoneException();
      }
      rethrow;
    }
  }

  /// Cancels a sent request, or unfriends.
  Future<void> remove(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
  }

  /// Calls [onChange] on any change to the signed-in user's friendships,
  /// and on every (re)subscribe — so anything missed while disconnected is
  /// caught up too. Returns the function that stops listening.
  ///
  /// The events themselves are ignored: a delete carries only a row id, and
  /// re-reading the list is cheap and always right.
  void Function() watch(String userId, void Function() onChange) {
    final channel = _client
        .channel('friendships:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          callback: (_) => onChange(),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) onChange();
        });
    return () => _client.removeChannel(channel);
  }
}
