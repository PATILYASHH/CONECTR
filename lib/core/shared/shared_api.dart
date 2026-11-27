import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../profile/profile_repository.dart';
import 'shared_entry.dart';

/// Supabase refused the access token (expired, signed out elsewhere).
class SessionRefusedException implements Exception {}

class SharedApiException implements Exception {
  SharedApiException(this.statusCode, this.message);

  final int statusCode;

  /// For the functions' own refusals, their code: `not_friends`,
  /// `entry_locked`, `entry_changed`, …
  final String message;

  /// Retrying won't help — the request itself is refused. Anything else
  /// (5xx, rate limits) is worth another try.
  bool get permanent =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  @override
  String toString() => 'SharedApiException($statusCode): $message';
}

/// Shared entries and friends over Supabase's REST API, with an access
/// token passed in — the same in the app and in the background job, which
/// has no Supabase client (see `SessionTokens`). Row-level security limits
/// every read to the signed-in account's own rows; every write goes through
/// the migration's functions.
class SharedApi {
  SharedApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String get _base => '${AppConfig.supabaseUrl}/rest/v1';

  Map<String, String> _headers(String token) => {
    'apikey': AppConfig.supabaseAnonKey,
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Future<List<SharedEntry>> fetchEntries(String token) async {
    final rows = await _get(token, 'shared_entries', {
      'select': '*',
      'order': 'created_at.asc',
    });
    return [
      for (final row in rows as List<dynamic>)
        SharedEntry.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// The account's username (null before it picks one) and its accepted
  /// friends — what XPENC may link persons to.
  Future<({String? username, List<Profile> friends})> fetchFriends(
    String token,
    String myId,
  ) async {
    final mine =
        await _get(token, 'profiles', {'select': 'username', 'id': 'eq.$myId'})
            as List<dynamic>;
    if (mine.isEmpty) return (username: null, friends: const <Profile>[]);
    const side = 'id,username,display_name';
    final rows =
        await _get(token, 'friendships', {
              'select':
                  'requester:profiles!friendships_requester_id_fkey($side),'
                  'addressee:profiles!friendships_addressee_id_fkey($side)',
              'status': 'eq.accepted',
            })
            as List<dynamic>;
    final friends = <Profile>[];
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final requester = row['requester'] as Map<String, dynamic>?;
      final addressee = row['addressee'] as Map<String, dynamic>?;
      final other = requester?['id'] == myId ? addressee : requester;
      if (other != null) friends.add(Profile.fromJson(other));
    }
    friends.sort((a, b) => a.username.compareTo(b.username));
    return (
      username: (mine.first as Map<String, dynamic>)['username'] as String?,
      friends: friends,
    );
  }

  Future<void> apply(String token, SharedOp op) => switch (op) {
    AddOp(:final clientRef, :final friendId, :final fields, :final isOpening) =>
      _rpc(token, 'add_shared_entry', {
        'p_client_ref': clientRef,
        'p_friend_id': friendId,
        ...fields.toParams(),
        'p_is_opening': isOpening,
      }),
    EditOp(:final clientRef, :final fields) => _rpc(
      token,
      'edit_shared_entry',
      {'p_client_ref': clientRef, ...fields.toParams()},
    ),
    DeleteOp(:final clientRef) => _rpc(token, 'delete_shared_entry', {
      'p_client_ref': clientRef,
    }),
    RespondOp(:final entryId, :final accept, :final version) => _rpc(
      token,
      'respond_shared_entry',
      {'p_id': entryId, 'p_accept': accept, 'p_expected_version': version},
    ),
  };

  Future<Object?> _get(
    String token,
    String table,
    Map<String, String> query,
  ) async {
    final res = await _client
        .get(
          Uri.parse('$_base/$table').replace(queryParameters: query),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  Future<void> _rpc(
    String token,
    String function,
    Map<String, Object?> params,
  ) async {
    final res = await _client
        .post(
          Uri.parse('$_base/rpc/$function'),
          headers: _headers(token),
          body: jsonEncode(params),
        )
        .timeout(const Duration(seconds: 30));
    _decode(res);
  }

  static Object? _decode(http.Response res) {
    if (res.statusCode == 401) throw SessionRefusedException();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var message = res.body;
      try {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        message = (json['message'] ?? json['error'] ?? message).toString();
      } catch (_) {}
      throw SharedApiException(res.statusCode, message);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}
