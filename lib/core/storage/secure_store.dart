import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../backup/auto_sync_settings.dart';
import '../backup/sync_rules.dart';
import '../backup/sync_state.dart';

/// Everything Connector needs to remember between launches that isn't
/// already in the Supabase session: the GitHub token (Supabase only hands
/// this back once, on the OAuth redirect — see [AuthService]), the chosen
/// backup folder, auto-sync settings and state. Also read by the background
/// sync job, which has no Supabase session of its own.
class SecureStore {
  SecureStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _githubTokenKey = 'github_provider_token';
  static const _githubLoginKey = 'github_login';
  static const _backupFolderUriKey = 'backup_folder_uri';
  static const _autoBackupKey = 'auto_backup';
  static const _autoPullKey = 'auto_pull';
  static const _deviceIdKey = 'device_id';
  static const _deviceNameKey = 'device_name';
  static const _syncStateKey = 'sync_state';

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

  Future<AutoSyncSettings> getAutoSyncSettings() async {
    const defaults = AutoSyncSettings.defaults;
    final mode = await _storage.read(key: _autoBackupKey);
    final pull = await _storage.read(key: _autoPullKey);
    return AutoSyncSettings(
      autoBackup: AutoBackup.values.asNameMap()[mode] ?? defaults.autoBackup,
      autoPull: pull == null ? defaults.autoPull : pull == 'true',
    );
  }

  Future<void> setAutoSyncSettings(AutoSyncSettings settings) async {
    await _storage.write(key: _autoBackupKey, value: settings.autoBackup.name);
    await _storage.write(key: _autoPullKey, value: '${settings.autoPull}');
  }

  Future<String?> getDeviceId() => _storage.read(key: _deviceIdKey);

  Future<void> setDeviceId(String id) =>
      _storage.write(key: _deviceIdKey, value: id);

  /// Null until the user renames this phone; see `DeviceIdentity`.
  Future<String?> getDeviceName() => _storage.read(key: _deviceNameKey);

  Future<void> setDeviceName(String name) =>
      _storage.write(key: _deviceNameKey, value: name);

  Future<SyncState> getSyncState() async {
    final raw = await _storage.read(key: _syncStateKey);
    if (raw == null) return SyncState();
    try {
      return SyncState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // Unreadable (e.g. written by a future version) — start clean rather
      // than wedge every sync on it.
      return SyncState();
    }
  }

  Future<void> saveSyncState(SyncState state) =>
      _storage.write(key: _syncStateKey, value: jsonEncode(state.toJson()));

  /// Every update in this isolate, in order. Shared by every [SecureStore]
  /// here, since a provider and a sync service may each hold their own.
  static Future<void> _stateWrites = Future.value();

  /// Load, change, save — the only way state should be written. Updates in
  /// one isolate run one after another, so none saves a copy loaded before
  /// another's change landed; across isolates, `SyncLock` keeps syncs apart.
  Future<SyncState> updateSyncState(void Function(SyncState s) change) {
    final update = _stateWrites.then((_) async {
      final state = await getSyncState();
      change(state);
      await saveSyncState(state);
      return state;
    });
    // A failed update mustn't wedge every later one.
    _stateWrites = update.then((_) {}, onError: (_) {});
    return update;
  }

  /// Everything but this phone's identity: a new random id after signing
  /// back in would make this phone's own uploads look like another phone's.
  Future<void> clearAll() async {
    final keep = {_deviceIdKey, _deviceNameKey};
    // A copy: deleting while iterating what readAll hands back can throw.
    final keys = (await _storage.readAll()).keys.toList();
    for (final key in keys) {
      if (!keep.contains(key)) await _storage.delete(key: key);
    }
  }
}
