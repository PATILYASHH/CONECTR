import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background/auto_sync.dart';
import '../../core/backup/backup_meta.dart';
import '../../core/backup/backup_sync_service.dart';
import '../../core/backup/sync_lock.dart';
import '../../core/backup/sync_rules.dart';
import '../../core/backup/sync_state.dart';
import '../../core/backup/sync_state_signal.dart';
import '../../core/notifications/app_notifications.dart';
import '../../core/platform/xpenc_launcher.dart';
import '../../core/providers.dart';

enum BackupBusy {
  /// Re-asking GitHub whether a recorded "Reconnect GitHub" still holds.
  checkingAccess,
  sync,
  upload,
  pull,
}

/// Everything the Backup tab shows. Rebuilt whole on every refresh.
class BackupView {
  const BackupView({
    required this.sync,
    this.busy,
    this.localModified,
    this.localName,
    this.thisDeviceId,
  });

  final SyncState sync;
  final BackupBusy? busy;

  /// The newest backup XPENC has written to the folder on this phone.
  final DateTime? localModified;
  final String? localName;

  final String? thisDeviceId;

  /// GitHub's backup came from another phone and this one hasn't imported
  /// it, so uploads from here wait (see `isFromElsewhere`).
  bool get waitingForImport {
    final remote = sync.remote;
    final deviceId = thisDeviceId;
    if (remote == null || deviceId == null) return false;
    return isFromElsewhere(
      remote,
      thisDeviceId: deviceId,
      baseCommitSha: sync.baseCommitSha,
    );
  }

  /// XPENC wrote a backup GitHub doesn't have yet.
  bool get uploadPending {
    final local = localModified;
    if (local == null || waitingForImport) return false;
    final handled = sync.lastHandledLocalModified;
    return handled == null || local.isAfter(handled);
  }

  BackupView withBusy(BackupBusy? busy) => BackupView(
    sync: sync,
    busy: busy,
    localModified: localModified,
    localName: localName,
    thisDeviceId: thisDeviceId,
  );
}

/// The Backup tab's state and actions. Errors from actions propagate to
/// the screen, which shows them via `SyncFailure`; the automatic check on
/// open records its own (see [AutoSyncRunner]).
class BackupController extends Notifier<BackupView> {
  BackupSyncService get _service => ref.read(backupSyncServiceProvider);

  @override
  BackupView build() {
    // Start over for a different account (sign-out included).
    ref.watch(currentUserIdProvider);
    // Whatever the background job changes shows here as it happens, not
    // at the next tap.
    Timer? debounce;
    final changes = SyncStateSignal.changes.listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 300), () {
        if (ref.mounted) refresh().ignore();
      });
    });
    ref.onDispose(() {
      debounce?.cancel();
      changes.cancel();
    });
    Future.microtask(_onFirstOpen);
    return BackupView(sync: SyncState());
  }

  Future<void> _onFirstOpen() async {
    // Notifications only matter once backup is set up — which reaching
    // this tab's dashboard means. Android asks at most once.
    final settings = await ref.read(secureStoreProvider).getAutoSyncSettings();
    if (settings.anyOn) await AppNotifications.requestPermission();
    await checkOnOpen();
  }

  /// Opening or returning to the app is itself a trigger: whatever the
  /// auto-sync settings say is due runs now, not at the next background
  /// slot.
  ///
  /// A "Reconnect GitHub" problem is asked about first, on its own — one
  /// request, no waiting behind a background run for the sync lock — so a
  /// problem that's already gone doesn't sit on screen for the length of a
  /// sync. Until that answer, the card says it's checking.
  Future<void> checkOnOpen() async {
    if (state.busy != null) return;
    state = state.withBusy(BackupBusy.checkingAccess);
    try {
      await _service.recheckAccess();
    } catch (_) {
      // Offline or GitHub down: the sync below says so, or retries.
    }
    if (!ref.mounted) return;
    state = state.withBusy(null);
    // The runner takes the lock itself.
    await _guard(BackupBusy.sync, lock: false, () {
      return AutoSyncRunner(
        _service,
        ref.read(secureStoreProvider),
      ).run(fromApp: true);
    });
  }

  Future<void> refresh() async {
    final sync = await _service.state();
    final local = await _service.newestLocalBackup().catchError((_) => null);
    final deviceId = await ref.read(deviceIdentityProvider).id();
    if (!ref.mounted) return;
    state = BackupView(
      sync: sync,
      busy: state.busy,
      localModified: local == null ? null : BackupSyncService.modifiedAt(local),
      localName: local?.name,
      thisDeviceId: deviceId,
    );
  }

  /// The sync icon: upload if GitHub's backup is this phone's to replace,
  /// then bring down anything from another phone. Never overwrites another
  /// phone's backup — that takes "Upload now" and a confirmation.
  Future<String> syncNow() async {
    if (state.busy != null) return 'Already syncing.';
    return _guard(BackupBusy.sync, () async {
      final up = await _service.upload(manual: true);
      final down = await _service.pull();
      return switch ((up, down)) {
        (_, Pulled(:final remote)) =>
          'New backup from ${remote.deviceName ?? 'another phone'} saved '
              'to the folder.',
        (Uploaded(), _) => 'Backed up to GitHub.',
        (RemoteNotImported(:final remote), _) =>
          'Import the backup from ${remote.deviceName ?? 'another phone'} '
              'first. Uploads from this phone wait until you do.',
        (NoLocalBackup(), NothingOnGithub()) =>
          'Nothing to sync yet. Make a backup in XPENC first.',
        _ => 'Everything is up to date.',
      };
    });
  }

  Future<UploadResult> upload({bool overwriteNewer = false}) {
    return _guard(
      BackupBusy.upload,
      () => _service.upload(manual: true, overwriteNewer: overwriteNewer),
    );
  }

  Future<PullResult> pullLatest() {
    return _guard(BackupBusy.pull, () => _service.pull(force: true));
  }

  /// Only opens it. XPENC takes the backup in and reports back through
  /// `XpencProvider`; the card goes once the next sync applies that report
  /// (or the user taps "I've imported it", for an older XPENC).
  Future<void> openXpenc() => XpencLauncher.open();

  /// The "I've imported it" button, for the backup the card showed.
  Future<void> confirmImported(RemoteBackup backup) async {
    try {
      await SyncLock.run(
        () => _service.confirmImported(backup.commitSha),
        wait: _lockWait,
      );
    } finally {
      if (ref.mounted) await refresh();
    }
  }

  /// Hides the card without vouching for the import — for a pulled backup
  /// that was this phone's own anyway.
  Future<void> dismissImport() async {
    await ref
        .read(secureStoreProvider)
        .updateSyncState((s) => s.clearPendingImport());
    await refresh();
  }

  /// Long enough for a background upload of a big backup to finish.
  static const _lockWait = Duration(minutes: 1);

  Future<T> _guard<T>(
    BackupBusy kind,
    Future<T> Function() action, {
    bool lock = true,
  }) async {
    state = state.withBusy(kind);
    try {
      return await (lock ? SyncLock.run(action, wait: _lockWait) : action());
    } finally {
      if (ref.mounted) {
        state = state.withBusy(null);
        await refresh();
      }
    }
  }
}

final backupControllerProvider = NotifierProvider<BackupController, BackupView>(
  BackupController.new,
);
