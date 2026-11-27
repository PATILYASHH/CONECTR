import 'package:saf_util/saf_util_platform_interface.dart' show SafDocumentFile;

import '../config/app_config.dart';
import '../device/device_identity.dart';
import '../storage/secure_store.dart';
import '../xpenc/xpenc_inbox.dart';
import 'backup_folder_service.dart';
import 'backup_meta.dart';
import 'backup_store.dart';
import 'git_blob_sha.dart';
import 'sync_errors.dart';
import 'sync_rules.dart';
import 'sync_state.dart';

export 'sync_errors.dart';

sealed class UploadResult {}

class Uploaded extends UploadResult {}

/// Nothing new since the last upload, or identical to the cloud's copy.
class UploadNotNeeded extends UploadResult {}

/// The cloud's backup came from another phone and this one hasn't imported it
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

class NothingRemote extends PullResult {}

/// One round trip between XPENC's shared backup folder and the account's
/// backup destination ([BackupStore]: GitHub, Google Drive or ExoCloud),
/// shared by the app's buttons and the background job
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
    required this._backups,
    required this._folder,
    required this._store,
    required this._device,
    this._inbox,
  });

  final BackupStore _backups;
  final BackupFolderService _folder;
  final SecureStore _store;
  final DeviceIdentity _device;

  /// What XPENC reads to take a pulled backup in by itself. Null in tests
  /// that don't care.
  final XpencInbox? _inbox;

  /// Where this service's backups go.
  BackupStore get backups => _backups;

  /// Connected to the destination and a folder chosen — without them
  /// there's nothing for auto-sync to do, and that isn't an error worth
  /// reporting.
  Future<bool> isSetUp() async =>
      await _backups.isConnected() && await _store.getBackupFolderUri() != null;

  /// The newest file XPENC has written to the folder, or null.
  Future<SafDocumentFile?> newestLocalBackup() async {
    final folderUri = await _store.getBackupFolderUri();
    if (folderUri == null) return null;
    return _folder.findLatestBackupFile(folderUri);
  }

  static DateTime modifiedAt(SafDocumentFile file) =>
      DateTime.fromMillisecondsSinceEpoch(file.lastModified, isUtc: true);

  /// Uploads this phone's newest XPENC backup if [uploadVerdict] allows it
  /// and it actually differs from the cloud's.
  ///
  /// [manual] skips the folder-only shortcut, so a tap always re-asks the
  /// cloud. [overwriteNewer] uploads even over another phone's backup —
  /// only after the user has confirmed [RemoteNotImported].
  Future<UploadResult> upload({
    bool manual = false,
    bool overwriteNewer = false,
  }) => _backups.guard(
    () => _upload(manual: manual, overwriteNewer: overwriteNewer),
  );

  Future<UploadResult> _upload({
    required bool manual,
    required bool overwriteNewer,
  }) async {
    await applyXpencImport();
    final folderUri = await _folderUri();
    final local = await _folder.findLatestBackupFile(folderUri);
    if (local == null) return NoLocalBackup();
    final localModified = modifiedAt(local);

    final state = await _store.getSyncState();
    final handled = state.lastHandledLocalModified;
    if (!manual && handled != null && !localModified.isAfter(handled)) {
      return UploadNotNeeded();
    }

    await _backups.ensureReady();
    final remote = await _backups.latest();
    if (!overwriteNewer) {
      final verdict = uploadVerdict(
        localModified,
        remote: remote,
        handledUpTo: handled,
        thisDeviceId: await _device.id(),
        baseVersionId: state.baseVersionId,
        baseCommittedAt: state.baseCommittedAt,
      );
      if (verdict != UploadVerdict.upload) {
        await _store.updateSyncState((s) {
          s.lastCheckAt = DateTime.now().toUtc();
          s.remote = remote;
          // Settled until XPENC writes something newer — or, if blocked,
          // until the user imports or overrides. Either way, no need for
          // auto-sync to keep asking the cloud about this file.
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
    final checkedSha = remote == null
        ? null
        : await _backups.contentShaOf(remote);
    if (checkedSha != null && checkedSha == gitBlobSha(bytes)) {
      await _store.updateSyncState((s) {
        s.lastHandledLocalModified = localModified;
        s.lastCheckAt = DateTime.now().toUtc();
        s.remote = remote;
        s.baseVersionId = remote!.versionId;
        s.baseCommittedAt = remote.committedAt;
        s.baseFileSha = checkedSha;
      });
      await _publish();
      return UploadNotNeeded();
    }

    final meta = BackupMeta(
      deviceId: await _device.id(),
      deviceName: await _device.name(),
      backupModifiedAt: localModified,
      sourceFileName: local.name,
    );
    // Replacing exactly the version just checked: if another phone
    // uploaded since, the store refuses instead of letting this replace a
    // backup that nobody looked at.
    final uploaded = await _backups.upload(bytes, meta, replacing: remote);
    final now = DateTime.now().toUtc();
    await _store.updateSyncState((s) {
      s.lastUploadAt = now;
      s.lastHandledLocalModified = localModified;
      s.lastCheckAt = now;
      s.remote = uploaded;
      s.baseVersionId = uploaded.versionId;
      s.baseCommittedAt = uploaded.committedAt;
      s.baseFileSha = gitBlobSha(bytes);
      // Whatever was pulled is no longer the cloud's latest — this is.
      s.clearPendingImport();
      s.clearProblem();
    });
    await _publish();
    return Uploaded();
  }

  /// The user says they've imported [versionId]'s backup into XPENC. From
  /// now on this phone's data is built on it, so uploads may replace it —
  /// but only with backups XPENC writes from here on: anything already in
  /// the folder was made before the import, from the old data. (XPENC's
  /// auto-backup runs as the app opens, i.e. just before the import.)
  ///
  /// [at]: when the import happened, if it's known to be earlier than now —
  /// XPENC's own report, read later; backups it wrote since hold new data.
  Future<void> confirmImported(String versionId, {DateTime? at}) async {
    final when = (at ?? DateTime.now()).toUtc();
    await _store.updateSyncState((s) {
      s.baseVersionId = versionId;
      // The server time of what's now the base, when it's known here.
      final base = s.pendingImport?.versionId == versionId
          ? s.pendingImport
          : s.remote?.versionId == versionId
          ? s.remote
          : null;
      s.baseCommittedAt = base?.committedAt;
      final handled = s.lastHandledLocalModified;
      if (handled == null || when.isAfter(handled)) {
        s.lastHandledLocalModified = when;
      }
      if (s.pendingImport?.versionId == versionId) {
        s.baseFileSha = s.pendingImportSha;
        s.clearPendingImport();
      }
    });
    await _publish();
  }

  /// Applies XPENC's own report of taking the pulled backup in (left
  /// through `XpencProvider`), before anything else this round acts on
  /// what's pending. Callers hold `SyncLock`.
  Future<void> applyXpencImport() async {
    final report = await _inbox?.takeImport();
    if (report == null) return;
    final state = await _store.getSyncState();
    final pending = state.pendingImport;
    if (pending == null || state.pendingImportSha != report.sha) return;
    await confirmImported(pending.versionId, at: report.at);
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
    await confirmImported(pending.versionId);
    return ImportHandoff.confirmed;
  }

  /// Saves the cloud's backup into the folder as [AppConfig.backupFileName]
  /// if [shouldPull] says it's worth it — or always, with [force] (the
  /// "Pull latest" button). Never imports it: only XPENC can, by hand.
  Future<PullResult> pull({bool force = false}) =>
      _backups.guard(() => _pull(force: force));

  Future<PullResult> _pull({required bool force}) async {
    await applyXpencImport();
    final folderUri = await _folderUri();
    final remote = await _backups.latest();
    final now = DateTime.now().toUtc();
    if (remote == null) {
      await _store.updateSyncState((s) => s.lastCheckAt = now);
      return NothingRemote();
    }

    final state = await _store.getSyncState();
    if (!force) {
      final pull = shouldPull(
        remote,
        thisDeviceId: await _device.id(),
        baseVersionId: state.baseVersionId,
        lastPulledVersionId: state.lastPulledVersionId,
        baseCommittedAt: state.baseCommittedAt,
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

    // Exactly the version recorded below, even if another phone uploaded
    // since — confirming the import later vouches for this version's data.
    final bytes = await _backups.download(remote);
    if (bytes == null) return NothingRemote();
    await _folder.writeRestoredBackup(
      folderUri,
      AppConfig.backupFileName,
      bytes,
    );
    await _store.updateSyncState((s) {
      s.lastCheckAt = now;
      s.lastPullAt = now;
      s.lastPulledVersionId = remote.versionId;
      s.remote = remote;
      s.pendingImport = remote;
      s.pendingImportSha = gitBlobSha(bytes);
      s.clearProblem();
    });
    await _publish(pendingBytes: bytes);
    return Pulled(remote);
  }

  Future<SyncState> state() => _store.getSyncState();

  /// A "Reconnect" problem recorded earlier — usually by the background
  /// job — asked about again, in one request and without waiting for a
  /// sync slot: that wait (up to half a minute, behind a background run)
  /// is what kept a problem that was already gone on screen. Clears it if
  /// the destination accepts this phone after all. Throws if it can't be
  /// reached.
  Future<void> recheckAccess() async {
    if (!(await _store.getSyncState()).problemNeedsReconnect) return;
    if (await _backups.accessWorks() != true) return;
    await _store.updateSyncState((s) {
      if (s.problemNeedsReconnect) s.clearProblem();
    });
  }

  /// A failure here mustn't fail the sync: XPENC simply sees the old state
  /// until the next round.
  Future<void> _publish({List<int>? pendingBytes}) async {
    final inbox = _inbox;
    if (inbox == null) return;
    try {
      await inbox.publish(
        await _store.getSyncState(),
        pendingBytes: pendingBytes,
      );
    } catch (_) {}
  }

  Future<String> _folderUri() async {
    final folderUri = await _store.getBackupFolderUri();
    if (folderUri == null) {
      throw SyncSetupException(
        'No backup folder chosen yet. Point Connector at XPENC\'s '
        '"Download/BACKUP XPENC" folder first.',
      );
    }
    return folderUri;
  }
}
