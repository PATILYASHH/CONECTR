import 'package:saf_util/saf_util_platform_interface.dart' show SafDocumentFile;

import '../config/app_config.dart';
import '../device/device_identity.dart';
import '../github/github_api.dart';
import '../storage/secure_store.dart';
import 'backup_folder_service.dart';
import 'backup_meta.dart';
import 'git_blob_sha.dart';
import 'sync_rules.dart';
import 'sync_state.dart';

/// Thrown for problems the UI should show as plain text, as opposed to a
/// bug — not signed in to GitHub, no folder chosen.
class SyncSetupException implements Exception {
  SyncSetupException(this.message);
  final String message;
}

sealed class UploadResult {}

class Uploaded extends UploadResult {}

/// Nothing new since the last upload, or identical to GitHub's copy.
class UploadNotNeeded extends UploadResult {}

/// GitHub's backup came from another phone and this one hasn't imported it
/// — uploading would replace that phone's data with this one's.
class RemoteNotImported extends UploadResult {
  RemoteNotImported(this.remote);
  final RemoteBackup remote;
}

class NoLocalBackup extends UploadResult {}

sealed class PullResult {}

class Pulled extends PullResult {
  Pulled(this.remote);
  final RemoteBackup remote;
}

class PullNotNeeded extends PullResult {}

/// What XPENC's "Tell Connector" link came to.
enum ImportHandoff {
  confirmed,

  /// XPENC imported some other file than the one Connector pulled.
  differentFile,

  /// No pulled backup is waiting to be imported.
  nothingPending,
}

class NothingOnGithub extends PullResult {}

/// One round trip between XPENC's shared backup folder and the user's
/// `XPENC-BACKUP` repo, shared by the app's buttons and the background job
/// (which has no Riverpod, hence plain constructor injection). Connector
/// never reads XPENC's private database — it only moves the JSON file XPENC
/// itself already knows how to export and import.
///
/// Every decision about *whether* to move a file is one of the tested rules
/// in `sync_rules.dart`; this class only does the I/O around them. Callers
/// hold `SyncLock` around each call, so the app and the background job
/// never sync at once.
class BackupSyncService {
  BackupSyncService({
    required this._github,
    required this._folder,
    required this._store,
    required this._device,
  });

  final GithubApi _github;
  final BackupFolderService _folder;
  final SecureStore _store;
  final DeviceIdentity _device;

  static const _repo = AppConfig.backupRepoName;
  static const _path = AppConfig.backupFileName;

  /// Both a GitHub token and a folder — without them there's nothing for
  /// auto-sync to do, and that isn't an error worth reporting.
  Future<bool> isSetUp() async =>
      await _store.getGithubToken() != null &&
      await _store.getBackupFolderUri() != null;

  /// The newest file XPENC has written to the folder, or null.
  Future<SafDocumentFile?> newestLocalBackup() async {
    final folderUri = await _store.getBackupFolderUri();
    if (folderUri == null) return null;
    return _folder.findLatestBackupFile(folderUri);
  }

  static DateTime modifiedAt(SafDocumentFile file) =>
      DateTime.fromMillisecondsSinceEpoch(file.lastModified, isUtc: true);

  /// Uploads this phone's newest XPENC backup if [uploadVerdict] allows it
  /// and it actually differs from GitHub's.
  ///
  /// [manual] skips the folder-only shortcut, so a tap always re-asks
  /// GitHub. [overwriteNewer] uploads even over another phone's backup —
  /// only after the user has confirmed [RemoteNotImported].
  Future<UploadResult> upload({
    bool manual = false,
    bool overwriteNewer = false,
  }) async {
    final ctx = await _context();
    final local = await _folder.findLatestBackupFile(ctx.folderUri);
    if (local == null) return NoLocalBackup();
    final localModified = modifiedAt(local);

    final state = await _store.getSyncState();
    final handled = state.lastHandledLocalModified;
    if (!manual && handled != null && !localModified.isAfter(handled)) {
      return UploadNotNeeded();
    }

    await _ensureRepoReady(ctx);
    final remote = await _latestRemote(ctx);
    if (!overwriteNewer) {
      final verdict = uploadVerdict(
        localModified,
        remote: remote,
        handledUpTo: handled,
        thisDeviceId: await _device.id(),
        baseCommitSha: state.baseCommitSha,
      );
      if (verdict != UploadVerdict.upload) {
        await _store.updateSyncState((s) {
          s.lastCheckAt = DateTime.now().toUtc();
          s.remote = remote;
          // Settled until XPENC writes something newer — or, if blocked,
          // until the user imports or overrides. Either way, no need for
          // auto-sync to keep asking GitHub about this file.
          if (handled == null || localModified.isAfter(handled)) {
            s.lastHandledLocalModified = localModified;
          }
        });
        return verdict == UploadVerdict.notImported
            ? RemoteNotImported(remote!)
            : UploadNotNeeded();
      }
    }

    final bytes = await _folder.readFile(local.uri);
    // The file as of the commit just checked, not as of now: if another
    // phone pushed since, GitHub refuses the write instead of letting it
    // replace a backup that nobody looked at.
    final checkedSha = remote == null
        ? null
        : await _github.getFileSha(
            ctx.token,
            ctx.owner,
            _repo,
            _path,
            ref: remote.commitSha,
          );
    if (checkedSha != null && checkedSha == gitBlobSha(bytes)) {
      await _store.updateSyncState((s) {
        s.lastHandledLocalModified = localModified;
        s.lastCheckAt = DateTime.now().toUtc();
        s.remote = remote;
        s.baseCommitSha = remote!.commitSha;
      });
      return UploadNotNeeded();
    }

    final meta = BackupMeta(
      deviceId: await _device.id(),
      deviceName: await _device.name(),
      backupModifiedAt: localModified,
      sourceFileName: local.name,
    );
    final commitSha = await _github.putFile(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
      contentBytes: bytes,
      commitMessage: meta.toCommitMessage(),
      existingSha: checkedSha,
    );
    final now = DateTime.now().toUtc();
    await _store.updateSyncState((s) {
      s.lastUploadAt = now;
      s.lastHandledLocalModified = localModified;
      s.lastCheckAt = now;
      s.remote = RemoteBackup(
        commitSha: commitSha,
        committedAt: now,
        meta: meta,
      );
      s.baseCommitSha = commitSha;
      // Whatever was pulled is no longer GitHub's latest — this is.
      s.clearPendingImport();
      s.clearProblem();
    });
    return Uploaded();
  }

  /// The user says they've imported [commitSha]'s backup into XPENC. From
  /// now on this phone's data is built on it, so uploads may replace it —
  /// but only with backups XPENC writes from here on: anything already in
  /// the folder was made before the import, from the old data. (XPENC's
  /// auto-backup runs as the app opens, i.e. just before the import.)
  Future<void> confirmImported(String commitSha) async {
    final now = DateTime.now().toUtc();
    await _store.updateSyncState((s) {
      s.baseCommitSha = commitSha;
      final handled = s.lastHandledLocalModified;
      if (handled == null || now.isAfter(handled)) {
        s.lastHandledLocalModified = now;
      }
      if (s.pendingImport?.commitSha == commitSha) s.clearPendingImport();
    });
  }

  /// XPENC's "Tell Connector" (`conectr://imported?sha=…`, see
  /// `import_links.dart`): [sha] fingerprints the file XPENC just imported.
  /// Confirms the pending import only if that's the very file Connector
  /// pulled — anything else XPENC imported isn't the data that came down.
  Future<ImportHandoff> confirmImportedFile(String sha) async {
    final state = await _store.getSyncState();
    final pending = state.pendingImport;
    if (pending == null) return ImportHandoff.nothingPending;
    if (state.pendingImportSha != sha) return ImportHandoff.differentFile;
    await confirmImported(pending.commitSha);
    return ImportHandoff.confirmed;
  }

  /// Saves GitHub's backup into the folder as [AppConfig.backupFileName]
  /// if [shouldPull] says it's worth it — or always, with [force] (the
  /// "Pull latest" button). Never imports it: only XPENC can, by hand.
  Future<PullResult> pull({bool force = false}) async {
    final ctx = await _context();
    final remote = await _latestRemote(ctx);
    final now = DateTime.now().toUtc();
    if (remote == null) {
      await _store.updateSyncState((s) => s.lastCheckAt = now);
      return NothingOnGithub();
    }

    final state = await _store.getSyncState();
    if (!force) {
      final pull = shouldPull(
        remote,
        thisDeviceId: await _device.id(),
        baseCommitSha: state.baseCommitSha,
        lastPulledCommitSha: state.lastPulledCommitSha,
      );
      if (!pull) {
        await _store.updateSyncState((s) {
          s.lastCheckAt = now;
          s.remote = remote;
          s.clearProblem();
        });
        return PullNotNeeded();
      }
    }

    // Exactly the commit recorded below, even if another phone pushed
    // since — confirming the import later vouches for this commit's data.
    final file = await _github.getFile(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
      ref: remote.commitSha,
    );
    if (file == null) return NothingOnGithub();
    await _folder.writeRestoredBackup(
      ctx.folderUri,
      AppConfig.backupFileName,
      file.contentBytes,
    );
    await _store.updateSyncState((s) {
      s.lastCheckAt = now;
      s.lastPullAt = now;
      s.lastPulledCommitSha = remote.commitSha;
      s.remote = remote;
      s.pendingImport = remote;
      s.pendingImportSha = gitBlobSha(file.contentBytes);
      s.clearProblem();
    });
    return Pulled(remote);
  }

  Future<SyncState> state() => _store.getSyncState();

  Future<RemoteBackup?> _latestRemote(_SyncContext ctx) async {
    final commit = await _github.getLatestCommit(
      ctx.token,
      ctx.owner,
      _repo,
      _path,
    );
    if (commit == null) return null;
    return RemoteBackup(
      commitSha: commit.sha,
      committedAt: commit.date.toUtc(),
      meta: BackupMeta.parse(commit.message),
    );
  }

  Future<_SyncContext> _context() async {
    final token = await _store.getGithubToken();
    if (token == null) {
      throw SyncSetupException('GitHub isn\'t connected yet.');
    }
    final folderUri = await _store.getBackupFolderUri();
    if (folderUri == null) {
      throw SyncSetupException(
        'No backup folder chosen yet. Point Connector at XPENC\'s '
        '"Download/BACKUP XPENC" folder first.',
      );
    }
    var owner = await _store.getGithubLogin();
    if (owner == null) {
      owner = await _github.getAuthenticatedLogin(token);
      await _store.setGithubLogin(owner);
    }
    return _SyncContext(token: token, folderUri: folderUri, owner: owner);
  }

  Future<void> _ensureRepoReady(_SyncContext ctx) async {
    if (!await _github.repoExists(ctx.token, ctx.owner, _repo)) {
      await _github.createPrivateRepo(ctx.token, _repo);
    }
  }
}

class _SyncContext {
  _SyncContext({
    required this.token,
    required this.folderUri,
    required this.owner,
  });

  final String token;
  final String folderUri;
  final String owner;
}
