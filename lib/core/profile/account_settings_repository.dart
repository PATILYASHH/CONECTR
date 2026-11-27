import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/backup_destination.dart';

/// The account's own settings row (`account_settings`, owner-only).
class AccountSettings {
  const AccountSettings({this.destination, this.exoCloudKeyCheck});

  /// Null: not chosen yet (no row).
  final BackupDestination? destination;

  /// Set once ExoCloud has a key; see `ExoCloudCrypto.keyCheck`.
  final String? exoCloudKeyCheck;
}

class AccountSettingsRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<AccountSettings> fetch(String userId) async {
    final row = await _client
        .from('account_settings')
        .select('backup_destination, exocloud_key_check')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return const AccountSettings();
    return AccountSettings(
      destination: BackupDestination.fromKey(
        row['backup_destination'] as String?,
      ),
      exoCloudKeyCheck: row['exocloud_key_check'] as String?,
    );
  }

  /// Update, else create. Not an upsert: the update grant leaves out
  /// `user_id`, which an upsert would also try to set.
  Future<void> setDestination(String userId, BackupDestination d) async {
    final changes = {
      'backup_destination': d.key,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final updated = await _client
        .from('account_settings')
        .update(changes)
        .eq('user_id', userId)
        .select('user_id');
    if (updated.isNotEmpty) return;
    await _client.from('account_settings').insert({
      'user_id': userId,
      ...changes,
    });
  }

  /// Only after [setDestination], so the row exists.
  Future<void> setExoCloudKeyCheck(String userId, String? check) async {
    await _client
        .from('account_settings')
        .update({
          'exocloud_key_check': check,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId);
  }
}
