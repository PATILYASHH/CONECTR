import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything Connector needs to remember between launches that isn't
/// already in the Supabase session: the GitHub token (Supabase only hands
/// this back once, on the OAuth redirect — see [AuthService]) and the
/// user's chosen backup folder / repo.
class SecureStore {
  SecureStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _githubTokenKey = 'github_provider_token';
  static const _githubLoginKey = 'github_login';
  static const _backupFolderUriKey = 'backup_folder_uri';
  static const _lastSyncedAtKey = 'last_synced_at';

  Future<void> setGithubToken(String token) =>
      _storage.write(key: _githubTokenKey, value: token);

  Future<String?> getGithubToken() => _storage.read(key: _githubTokenKey);

  Future<void> setGithubLogin(String login) =>
      _storage.write(key: _githubLoginKey, value: login);

  Future<String?> getGithubLogin() => _storage.read(key: _githubLoginKey);

  Future<void> setBackupFolderUri(String uri) =>
      _storage.write(key: _backupFolderUriKey, value: uri);

  Future<String?> getBackupFolderUri() =>
      _storage.read(key: _backupFolderUriKey);

  Future<void> setLastSyncedAt(DateTime time) =>
      _storage.write(key: _lastSyncedAtKey, value: time.toIso8601String());

  Future<DateTime?> getLastSyncedAt() async {
    final raw = await _storage.read(key: _lastSyncedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> clearAll() => _storage.deleteAll();
}
