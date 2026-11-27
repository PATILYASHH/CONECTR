import 'dart:math';
import 'dart:typed_data';

import '../backup/backup_destination.dart';
import '../backup/backup_meta.dart';
import '../backup/backup_store.dart';
import '../backup/git_blob_sha.dart';
import '../backup/sync_errors.dart';
import '../shared/session_tokens.dart';
import '../storage/secure_store.dart';
import 'exocloud_api.dart';
import 'exocloud_crypto.dart';

/// Signed in, but no Supabase token just now (offline). Retried next run.
class ExoCloudOfflineException implements Exception {
  const ExoCloudOfflineException();
}

/// Backups in ExoCloud: encrypted on this phone, uploaded to the user's own
/// folder of the `exocloud` bucket, and committed as the new latest by
/// `exocloud_commit`, which refuses if another phone got there first.
class ExoCloudBackupStore implements BackupStore {
  ExoCloudBackupStore(
    this._api,
    this._store, {
    Future<TokenResult> Function()? token,
  }) : _token = token ?? SessionTokens.get;

  final ExoCloudApi _api;
  final SecureStore _store;
  final Future<TokenResult> Function() _token;

  /// Rows already read this run, by id.
  final _rows = <String, ExoCloudRow>{};

  @override
  BackupDestination get destination => BackupDestination.exoCloud;

  @override
  Future<bool> isConnected() async => await _store.getExoCloudKey() != null;

  @override
  Future<T> guard<T>(Future<T> Function() attempt) => attempt();

  /// Nothing here to reconnect: a signed-out phone shows the login screen.
  @override
  Future<bool?> accessWorks() async => null;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<RemoteBackup?> latest() async {
    final session = await _session();
    final row = await _api.row(session.token);
    return row == null ? null : _remember(row);
  }

  @override
  Future<String?> contentShaOf(RemoteBackup backup) async =>
      (await _rowOf(backup))?.contentSha;

  @override
  Future<Uint8List?> download(RemoteBackup backup) async {
    final row = await _rowOf(backup);
    if (row == null) return null;
    final session = await _session();
    final sealed = await _api.downloadObject(session.token, row.objectPath);
    if (sealed == null) return null;
    return ExoCloudCrypto.decrypt(sealed, await _key());
  }

  @override
  Future<RemoteBackup> upload(
    List<int> bytes,
    BackupMeta meta, {
    required RemoteBackup? replacing,
  }) async {
    final session = await _session();
    final sealed = await ExoCloudCrypto.encrypt(bytes, await _key());
    final path = '${session.userId}/${_randomName()}.exc';
    await _api.uploadObject(session.token, path, sealed);

    final ({ExoCloudRow backup, List<String> removed}) committed;
    try {
      committed = await _api.commit(
        session.token,
        objectPath: path,
        replacingId: replacing?.versionId,
        sizeBytes: sealed.length,
        deviceId: meta.deviceId,
        deviceName: meta.deviceName,
        backupModifiedAt: meta.backupModifiedAt,
        sourceFile: meta.sourceFileName,
        contentSha: gitBlobSha(bytes),
      );
    } catch (_) {
      // Not the latest after all (or not committed at all): take the
      // object back out, so it never stands as an orphan.
      await _api.deleteObjects(session.token, [path]).catchError((_) {});
      rethrow;
    }
    // Retention's leftovers; a failure only leaves them for next time.
    await _api
        .deleteObjects(session.token, committed.removed)
        .catchError((_) {});
    return _remember(committed.backup);
  }

  RemoteBackup _remember(ExoCloudRow row) {
    _rows[row.id] = row;
    return RemoteBackup(
      versionId: row.id,
      committedAt: row.createdAt,
      meta: BackupMeta(
        deviceId: row.deviceId,
        deviceName: row.deviceName,
        backupModifiedAt: row.backupModifiedAt,
        sourceFileName: row.sourceFile,
      ),
    );
  }

  Future<ExoCloudRow?> _rowOf(RemoteBackup backup) async {
    final known = _rows[backup.versionId];
    if (known != null) return known;
    final session = await _session();
    final row = await _api.row(session.token, id: backup.versionId);
    if (row != null) _rows[row.id] = row;
    return row;
  }

  Future<List<int>> _key() async {
    final key = await _store.getExoCloudKey();
    if (key == null) {
      throw SyncSetupException(
        'Enter your ExoCloud recovery key on this phone to sync.',
      );
    }
    return key;
  }

  Future<({String token, String userId})> _session() async {
    return switch (await _token()) {
      HaveToken(:final accessToken, :final userId) => (
        token: accessToken,
        userId: userId,
      ),
      SignedOut() => throw SyncSetupException(
        'Sign in to Connector to use ExoCloud.',
      ),
      TokenUnavailable() => throw const ExoCloudOfflineException(),
    };
  }

  static String _randomName() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
