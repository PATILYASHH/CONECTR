import 'dart:typed_data';

import '../backup/backup_destination.dart';
import '../backup/backup_meta.dart';
import '../backup/backup_store.dart';
import '../backup/sync_errors.dart';
import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'github_api.dart';

/// Backups as commits of one file in the user's private `XPENC-BACKUP`
/// repo. A version is a commit; the commit message carries [BackupMeta].
class GithubBackupStore implements BackupStore {
  GithubBackupStore(this._github, this._store);

  final GithubApi _github;
  final SecureStore _store;

  static const _repo = AppConfig.backupRepoName;
  static const _path = AppConfig.backupFileName;

  /// Blob shas already looked up this run — `contentShaOf` and `upload`
  /// ask about the same commit.
  final _shaAt = <String, String?>{};

  @override
  BackupDestination get destination => BackupDestination.github;

  @override
  Future<bool> isConnected() async => await _store.getGithubToken() != null;

  /// GitHub answered 401. Before that becomes "Reconnect GitHub" — a red
  /// card, a notification, auto-sync paused — make sure it's true:
  ///
  /// * the token may have been replaced since this run read it (connected
  ///   again in the app while the background job ran): try once more with
  ///   the new one;
  /// * GitHub may refuse one request yet, asked straight after, accept the
  ///   token (`GET /user`): nothing to reconnect, try again next run.
  ///
  /// Only a token GitHub itself calls bad gets through as the 401.
  @override
  Future<T> guard<T>(Future<T> Function() attempt) async {
    final used = await _store.getGithubToken();
    try {
      return await attempt();
    } on GithubApiException catch (e) {
      if (e.statusCode != 401 || used == null) rethrow;
      final current = await _store.getGithubToken();
      if (current != null && current != used) return attempt();
      if (await _github.tokenWorks(used)) throw GithubAuthGlitchException();
      rethrow;
    }
  }

  @override
  Future<bool?> accessWorks() async {
    final token = await _store.getGithubToken();
    if (token == null) return false;
    return _github.tokenWorks(token);
  }

  @override
  Future<void> ensureReady() async {
    final ctx = await _context();
    if (!await _github.repoExists(ctx.token, ctx.owner, _repo)) {
      await _github.createPrivateRepo(ctx.token, _repo);
    }
  }

  @override
  Future<RemoteBackup?> latest() async {
    final ctx = await _context();
    final commit = await _github.getLatestCommit(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
    );
    return commit == null ? null : _toRemote(commit);
  }

  @override
  Future<String?> contentShaOf(RemoteBackup backup) async {
    if (_shaAt.containsKey(backup.versionId)) return _shaAt[backup.versionId];
    final ctx = await _context();
    final sha = await _github.getFileSha(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
      ref: backup.versionId,
    );
    return _shaAt[backup.versionId] = sha;
  }

  @override
  Future<Uint8List?> download(RemoteBackup backup) async {
    final ctx = await _context();
    final file = await _github.getFile(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
      ref: backup.versionId,
    );
    return file?.contentBytes;
  }

  /// The file as of [replacing], not as of now: if another phone pushed
  /// since, GitHub refuses the write instead of letting it replace a backup
  /// that nobody looked at.
  @override
  Future<RemoteBackup> upload(
    List<int> bytes,
    BackupMeta meta, {
    required RemoteBackup? replacing,
  }) async {
    final ctx = await _context();
    final existingSha = replacing == null
        ? null
        : await contentShaOf(replacing);
    final commit = await _github.putFile(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
      contentBytes: bytes,
      commitMessage: meta.toCommitMessage(),
      existingSha: existingSha,
    );
    return RemoteBackup(
      versionId: commit.sha,
      committedAt: commit.date.toUtc(),
      meta: meta,
    );
  }

  RemoteBackup _toRemote(GithubCommit commit) => RemoteBackup(
    versionId: commit.sha,
    committedAt: commit.date.toUtc(),
    meta: BackupMeta.parse(commit.message),
  );

  Future<({String token, String owner})> _context() async {
    final token = await _store.getGithubToken();
    if (token == null) {
      throw SyncSetupException("GitHub isn't connected yet.");
    }
    var owner = await _store.getGithubLogin();
    if (owner == null) {
      owner = await _github.getAuthenticatedLogin(token);
      await _store.setGithubLogin(owner);
    }
    return (token: token, owner: owner);
  }
}
