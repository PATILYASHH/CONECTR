import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../backup/auto_sync_settings.dart';
import '../backup/sync_rules.dart';
import '../backup/sync_state.dart';
import '../backup/sync_state_signal.dart';

/// The phone's keystore refused a read or write — usually for a moment
/// (two engines starting at once, the device still locked). Nothing was
/// deleted; the next try usually works.
class SecureStoreException implements Exception {
  SecureStoreException(this.key, this.cause);

  final String key;
  final Object cause;

  @override
  String toString() => "SecureStoreException($key): $cause";
}

/// Everything Connector needs to remember between launches that isn't
/// already in the Supabase session: the GitHub token (Supabase only hands
/// this back once, on the OAuth redirect — see [AuthService]), the chosen
/// backup folder, auto-sync settings and state. Also read by the background
/// sync job, which has no Supabase session of its own.
class SecureStore {
  SecureStore() : _storage = const FlutterSecureStorage(aOptions: _android);

  /// `resetOnError` is on by default, and it means: on any keystore hiccup,
  /// delete *everything* — the GitHub token, the folder, sync state. The app
  /// and the background job are two engines in one process, so a hiccup
  /// is no rarity; each one silently disconnected GitHub. Off, a failed read
  /// is just an error ([SecureStoreException]) that the next run retries.
  static const _android = AndroidOptions(resetOnError: false);

  final FlutterSecureStorage _storage;

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      throw SecureStoreException(key, e);
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      throw SecureStoreException(key, e);
    }
  }

  static const _githubTokenKey = 'github_provider_token';
  static const _githubLoginKey = 'github_login';
  static const _backupFolderUriKey = 'backup_folder_uri';
  static const _autoBackupKey = 'auto_backup';
  static const _autoPullKey = 'auto_pull';
  static const _deviceIdKey = 'device_id';
  static const _deviceNameKey = 'device_name';
  static const _syncStateKey = 'sync_state';

  Future<void> setGithubToken(String token) =>
      _write(_githubTokenKey, token);

  Future<String?> getGithubToken() => _read(_githubTokenKey);

  Future<void> setGithubLogin(String login) =>
      _write(_githubLoginKey, login);

  Future<String?> getGithubLogin() => _read(_githubLoginKey);

  Future<void> setBackupFolderUri(String uri) =>
      _write(_backupFolderUriKey, uri);

  Future<String?> getBackupFolderUri() =>
      _read(_backupFolderUriKey);

  Future<AutoSyncSettings> getAutoSyncSettings() async {
    const defaults = AutoSyncSettings.defaults;
    final mode = await _read(_autoBackupKey);
    final pull = await _read(_autoPullKey);
    return AutoSyncSettings(
      autoBackup: AutoBackup.values.asNameMap()[mode] ?? defaults.autoBackup,
      autoPull: pull == null ? defaults.autoPull : pull == 'true',
    );
  }

  Future<void> setAutoSyncSettings(AutoSyncSettings settings) async {
    await _write(_autoBackupKey, settings.autoBackup.name);
    await _write(_autoPullKey, '${settings.autoPull}');
  }

  Future<String?> getDeviceId() => _read(_deviceIdKey);

  Future<void> setDeviceId(String id) =>
      _write(_deviceIdKey, id);

  /// Null until the user renames this phone; see `DeviceIdentity`.
  Future<String?> getDeviceName() => _read(_deviceNameKey);

  Future<void> setDeviceName(String name) =>
      _write(_deviceNameKey, name);

  Future<SyncState> getSyncState() async {
    final raw = await _read(_syncStateKey);
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
      _write(_syncStateKey, jsonEncode(state.toJson()));

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
      SyncStateSignal.notify();
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
    final Map<String, String> all;
    try {
      all = await _storage.readAll();
    } on PlatformException catch (e) {
      throw SecureStoreException('*', e);
    }
    for (final key in all.keys.toList()) {
      if (!keep.contains(key)) await _storage.delete(key: key);
    }
  }
}
