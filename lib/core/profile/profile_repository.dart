import 'package:supabase_flutter/supabase_flutter.dart';

class Profile {
  const Profile({required this.id, required this.username, this.displayName});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
  );

  final String id;
  final String username;
  final String? displayName;
}

/// Someone else claimed the username between the availability check and
/// the save — the database's unique constraint is the real referee.
class UsernameTakenException implements Exception {}

/// The `profiles` table and its RPCs (see `supabase/migrations/`). RLS lets
/// a user read and write only their own row, so every call here is scoped
/// to the signed-in user by the database itself, not by this class.
class ProfileRepository {
  static const _columns = 'id, username, display_name';

  SupabaseClient get _client => Supabase.instance.client;

  /// Null if this account hasn't picked a username yet.
  Future<Profile?> fetchMine(String userId) async {
    final row = await _client
        .from('profiles')
        .select(_columns)
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<bool> isUsernameAvailable(String username) async {
    final available = await _client.rpc(
      'username_available',
      params: {'p_username': username},
    );
    return available as bool;
  }

  /// Throws [UsernameTakenException] if [username] went to someone else
  /// since it was checked.
  Future<Profile> claimUsername(String username) async {
    try {
      final row = await _client
          .from('profiles')
          .insert({'id': _client.auth.currentUser!.id, 'username': username})
          .select(_columns)
          .single();
      return Profile.fromJson(row);
    } on PostgrestException catch (e) {
      // 23505 = unique violation. Only the username one means "taken" — a
      // primary-key clash would be this account saving twice.
      if (e.code == '23505' && e.message.contains('username')) {
        throw UsernameTakenException();
      }
      rethrow;
    }
  }
}
