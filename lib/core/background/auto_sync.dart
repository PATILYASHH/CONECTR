import 'dart:ui';

import 'package:workmanager/workmanager.dart';

import '../backup/auto_sync_settings.dart';
import '../backup/backup_folder_service.dart';
import '../backup/backup_sync_service.dart';
import '../backup/sync_failure.dart';
import '../backup/sync_lock.dart';
import '../backup/sync_rules.dart';
import '../device/device_identity.dart';
import '../github/github_api.dart';
import '../notifications/app_notifications.dart';
import '../storage/secure_store.dart';
import '../xpenc/xpenc_inbox.dart';

const _taskName = 'connector-auto-sync';

/// Entry point of the background isolate WorkManager starts. No Riverpod,
/// no Supabase — just the store, GitHub and the folder.
@pragma('vm:entry-point')
void autoSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    final store = SecureStore();
    await AutoSyncRunner(
      BackupSyncService(
        github: GithubApi(),
        folder: BackupFolderService(),
        store: store,
        device: DeviceIdentity(store),
        inbox: FileXpencInbox(),
      ),
      store,
    ).run(fromApp: false);
    // Always "success": a failed run is recorded and retried on schedule,
    // not by WorkManager's own backoff.
    return true;
  });
}

/// One auto-sync pass: upload if due, then check for a newer backup if
/// due. Runs from the background job, and from the app each time it opens.
class AutoSyncRunner {
  AutoSyncRunner(this._service, this._store);

  final BackupSyncService _service;
  final SecureStore _store;

  /// Skipped if another sync is already running — it's doing the same
  /// work. The app waits a little first, so its dashboard shows the result.
  Future<void> run({required bool fromApp}) async {
    try {
      await SyncLock.run(
        () => _run(fromApp: fromApp),
        wait: fromApp ? const Duration(seconds: 30) : Duration.zero,
      );
    } on SyncBusyException {
      return;
    }
  }

  Future<void> _run({required bool fromApp}) async {
    if (!await _service.isSetUp()) return;
    // XPENC may have taken the pulled backup in since the last round.
    await _service.applyXpencImport();
    final settings = await _store.getAutoSyncSettings();
    final state = await _store.getSyncState();
    final now = DateTime.now().toUtc();

    try {
      if (isAutoBackupDue(
        settings.autoBackup,
        state.lastAutoBackupRunAt,
        now,
      )) {
        await _service.upload();
        await _store.updateSyncState((s) => s.lastAutoBackupRunAt = now);
      }
      if (settings.autoPull &&
          (fromApp || isPullCheckDue(state.lastPullCheckAt, now))) {
        final result = await _service.pull();
        await _store.updateSyncState((s) => s.lastPullCheckAt = now);
        // In the app, the dashboard's own card says it; a notification on
        // top would be noise.
        if (result is Pulled && !fromApp) {
          await AppNotifications.newBackup(result.remote);
        }
      }
    } catch (e) {
      final failure = SyncFailure.from(e);
      if (failure.transient) return;
      final previous = state.problem;
      await _store.updateSyncState((s) {
        s.problem = failure.message;
        s.problemNeedsReconnect = failure.needsReconnect;
      });
      // Once per distinct problem, not on every 15-minute retry.
      if (!fromApp && previous != failure.message) {
        await AppNotifications.backupPaused(failure.message);
      }
    }
  }
}

class AutoSyncScheduler {
  /// Once, in `main`, before anything is scheduled.
  static Future<void> initialize() =>
      Workmanager().initialize(autoSyncDispatcher);

  /// Idempotent — called whenever settings or backup setup change.
  static Future<void> apply(
    AutoSyncSettings settings, {
    required bool backupReady,
  }) async {
    if (!backupReady || !settings.anyOn) return cancel();
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      // "After every XPENC backup" checks the folder often; that check is
      // local-only unless XPENC actually wrote something new.
      frequency: settings.autoBackup == AutoBackup.afterXpencBackup
          ? const Duration(minutes: 15)
          : const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancel() => Workmanager().cancelByUniqueName(_taskName);
}
