import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../backup/backup_destination.dart';
import '../backup/backup_meta.dart';
import '../backup/backup_store.dart';
import '../backup/git_blob_sha.dart';
import '../backup/sync_errors.dart';
import '../storage/secure_store.dart';
import 'drive_api.dart';
import 'google_auth.dart';

/// Drive access is gone (revoked, or consent needed again). Only
/// reconnecting Google Drive fixes it.
class DriveNotAuthorizedException implements Exception {
  const DriveNotAuthorizedException();
}

/// Backups as files in a visible `XPENC Backup` folder in the user's own
/// Drive — one new file per upload, the newest by Drive's `createdTime`
/// being "latest". Drive has no compare-and-swap, so an upload is checked
/// afterwards: if anything else was created since the version it replaced,
/// it takes itself back out and reports a conflict.
class DriveBackupStore implements BackupStore {
  DriveBackupStore(
    this._api,
    this._store, {
    Future<String?> Function(String email)? token,
    Future<void> Function(String token)? forgetToken,
  }) : _fetchToken = token ?? GoogleAuth.driveToken,
       _forgetToken = forgetToken ?? GoogleAuth.forgetToken;

  final DriveApi _api;
  final SecureStore _store;
  final Future<String?> Function(String email) _fetchToken;
  final Future<void> Function(String token) _forgetToken;

  static const folderName = 'XPENC Backup';
  static const _folderTag = 'backupFolder';
  static const _backupTag = 'backup';

  /// Newest kept; older ones are deleted after each successful upload.
  static const keep = 30;

  String? _token;
  final _files = <String, DriveFile>{};

  @override
  BackupDestination get destination => BackupDestination.googleDrive;

  @override
  Future<bool> isConnected() async => await _store.getDriveEmail() != null;

  /// Access tokens last about an hour and Play Services caches them; a 401
  /// usually means a stale one. Forget it and try once more with a fresh
  /// token before calling it revoked.
  @override
  Future<T> guard<T>(Future<T> Function() attempt) async {
    try {
      return await attempt();
    } on DriveApiException catch (e) {
      final stale = _token;
      if (e.statusCode != 401 || stale == null) rethrow;
      _token = null;
      await _forgetToken(stale).catchError((_) {});
      return attempt();
    }
  }

  @override
  Future<bool?> accessWorks() async {
    final email = await _store.getDriveEmail();
    if (email == null) return false;
    return await _fetchToken(email) != null;
  }

  @override
  Future<void> ensureReady() async {
    final token = await _session();
    final cached = await _store.getDriveFolderId();
    if (cached != null) {
      final folder = await _api.getFile(token, cached);
      if (folder != null && !folder.trashed) return;
    }
    final id =
        await _api.findFolder(token, _folderTag) ??
        await _api.createFolder(token, folderName, _folderTag);
    await _store.setDriveFolderId(id);
  }

  /// Found by tag, not by folder, so a second folder from two phones
  /// racing to create one doesn't matter.
  @override
  Future<RemoteBackup?> latest() async {
    final files = await _api.listTagged(
      await _session(),
      _backupTag,
      pageSize: 1,
      firstPageOnly: true,
    );
    return files.isEmpty ? null : _remember(files.first);
  }

  @override
  Future<String?> contentShaOf(RemoteBackup backup) async =>
      (await _fileOf(backup))?.appProperties['contentSha'];

  @override
  Future<Uint8List?> download(RemoteBackup backup) async =>
      _api.download(await _session(), backup.versionId);

  @override
  Future<RemoteBackup> upload(
    List<int> bytes,
    BackupMeta meta, {
    required RemoteBackup? replacing,
  }) async {
    final token = await _session();
    final folderId = await _store.getDriveFolderId();
    if (folderId == null) await ensureReady();
    final created = await _api.upload(
      token,
      name: fileName(meta),
      parentId: (await _store.getDriveFolderId())!,
      appProperties: appPropertiesOf(meta, gitBlobSha(bytes)),
      bytes: bytes,
    );

    // Did anyone else's backup land after the one this replaces?
    final since = await _api.listTagged(
      token,
      _backupTag,
      createdAfter: replacing?.committedAt,
    );
    if (since.any((f) => f.id != created.id)) {
      // Deleting our own file must work — if it didn't, it would quietly
      // stand as latest. So that error wins over the conflict.
      await _api.delete(token, created.id);
      throw const BackupConflictException();
    }

    final all = await _api.listTagged(token, _backupTag);
    for (final old in all.skip(keep)) {
      if (old.id == created.id) continue;
      await _api.delete(token, old.id).catchError((_) {});
    }
    return _remember(created);
  }

  /// `XPENC 2026-11-27 09.40 — Pixel 7.json` — for people; Connector
  /// itself goes by tags and Drive's times.
  static String fileName(BackupMeta meta) =>
      'XPENC ${DateFormat('yyyy-MM-dd HH.mm').format(meta.backupModifiedAt.toLocal())}'
      ' — ${meta.deviceName}.json';

  /// Every key+value stays under Drive's 124-byte limit: device names are
  /// capped at 40 characters, file names here at 60.
  static Map<String, String> appPropertiesOf(BackupMeta meta, String sha) => {
    'connector': _backupTag,
    'deviceId': meta.deviceId,
    'deviceName': meta.deviceName,
    'backupModified': meta.backupModifiedAt.toUtc().toIso8601String(),
    'sourceFile': meta.sourceFileName.length > 60
        ? meta.sourceFileName.substring(0, 60)
        : meta.sourceFileName,
    'contentSha': sha,
  };

  /// A file without readable tags is still a backup, just one without
  /// metadata — like an old-style GitHub commit.
  static BackupMeta? metaOf(DriveFile file) {
    final p = file.appProperties;
    final deviceId = p['deviceId'];
    final deviceName = p['deviceName'];
    final modified = DateTime.tryParse(p['backupModified'] ?? '');
    if (deviceId == null || deviceName == null || modified == null) {
      return null;
    }
    return BackupMeta(
      deviceId: deviceId,
      deviceName: deviceName,
      backupModifiedAt: modified.toUtc(),
      sourceFileName: p['sourceFile'] ?? '',
    );
  }

  RemoteBackup _remember(DriveFile file) {
    _files[file.id] = file;
    return RemoteBackup(
      versionId: file.id,
      committedAt: file.createdTime!,
      meta: metaOf(file),
    );
  }

  Future<DriveFile?> _fileOf(RemoteBackup backup) async {
    final known = _files[backup.versionId];
    if (known != null) return known;
    final file = await _api.getFile(await _session(), backup.versionId);
    if (file != null) _files[file.id] = file;
    return file;
  }

  Future<String> _session() async {
    final cached = _token;
    if (cached != null) return cached;
    final email = await _store.getDriveEmail();
    if (email == null) {
      throw SyncSetupException("Google Drive isn't connected yet.");
    }
    final token = await _fetchToken(email);
    if (token == null) throw const DriveNotAuthorizedException();
    return _token = token;
  }
}
