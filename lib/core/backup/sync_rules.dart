import 'backup_meta.dart';

/// The rules deciding what auto-sync does — kept free of I/O so each one is
/// tested on its own (see `test/sync_rules_test.dart`). They're the part
/// that could overwrite someone's newer backup if they were wrong.
///
/// None of them asks "which file is newer?". A file's time says when XPENC
/// wrote it, not how new the data in it is: XPENC's auto-backup runs
/// whenever the app opens, so a phone left unused for a week writes a
/// brand-new file of week-old data the moment someone opens XPENC to import
/// the other phone's backup. Instead, like `git push`, this phone may only
/// replace the backup on GitHub if that backup is one this phone already
/// has — its own upload, or one it imported.

enum AutoBackup { off, afterXpencBackup, daily, weekly }

/// Background runs are scheduled "about" every period; WorkManager is free
/// to run one a little early. Checks fire once this much of the period has
/// passed, so an early run doesn't skip a whole cycle.
const _pullCheckEvery = Duration(minutes: 50);

bool isAutoBackupDue(AutoBackup mode, DateTime? lastRunAt, DateTime now) {
  final every = switch (mode) {
    AutoBackup.off => null,
    // Every run — the upload itself goes no further than listing the
    // folder unless XPENC has written something new.
    AutoBackup.afterXpencBackup => Duration.zero,
    AutoBackup.daily => const Duration(days: 1),
    AutoBackup.weekly => const Duration(days: 7),
  };
  if (every == null) return false;
  if (lastRunAt == null) return true;
  return now.difference(lastRunAt) >= every;
}

bool isPullCheckDue(DateTime? lastCheckAt, DateTime now) {
  return lastCheckAt == null || now.difference(lastCheckAt) >= _pullCheckEvery;
}

/// The cloud's backup holds data this phone doesn't have: another phone (or
/// a hand edit) made it, and this phone hasn't imported it. [baseVersionId]
/// is the version this phone's data is known to be built on — its own last
/// upload, or the one it last confirmed importing.
///
/// [baseCommittedAt] is that version's server time. A remote no newer than
/// it is an *older* backup become latest again — the newest one deleted by
/// hand in Drive, or force-pushed away on GitHub. Pulling it would hand
/// XPENC old data that its "no local changes" check could take in by
/// itself, so it never counts. Server times only: phones' clocks are still
/// never compared.
bool isFromElsewhere(
  RemoteBackup remote, {
  required String thisDeviceId,
  required String? baseVersionId,
  DateTime? baseCommittedAt,
}) {
  if (remote.versionId == baseVersionId) return false;
  if (baseCommittedAt != null && !remote.committedAt.isAfter(baseCommittedAt)) {
    return false;
  }
  return remote.deviceId != thisDeviceId;
}

enum UploadVerdict {
  upload,

  /// Nothing this phone has is newer than what GitHub already holds.
  upToDate,

  /// GitHub's backup came from elsewhere; uploading would throw its data
  /// away, which only the user can decide.
  notImported,
}

/// The upload rule. [handledUpTo] is the newest local backup already dealt
/// with: uploaded, or written before an import and so built on old data.
UploadVerdict uploadVerdict(
  DateTime localModified, {
  required RemoteBackup? remote,
  required DateTime? handledUpTo,
  required String thisDeviceId,
  required String? baseVersionId,
  DateTime? baseCommittedAt,
}) {
  // Nothing to lose — even a backup written before an import beats none.
  if (remote == null) return UploadVerdict.upload;
  if (isFromElsewhere(
    remote,
    thisDeviceId: thisDeviceId,
    baseVersionId: baseVersionId,
    baseCommittedAt: baseCommittedAt,
  )) {
    return UploadVerdict.notImported;
  }
  if (handledUpTo != null && !localModified.isAfter(handledUpTo)) {
    return UploadVerdict.upToDate;
  }
  // This phone's own upload was timed by this phone's clock, so here — and
  // only here — the two times compare honestly.
  if (remote.deviceId == thisDeviceId &&
      !localModified.isAfter(remote.backupModifiedAt)) {
    return UploadVerdict.upToDate;
  }
  return UploadVerdict.upload;
}

/// The pull rule: bring GitHub's backup down whenever it holds data this
/// phone doesn't have and it hasn't been pulled already. Never by time — a
/// stale phone's fresh file must not hide the other phone's newer data.
bool shouldPull(
  RemoteBackup remote, {
  required String thisDeviceId,
  required String? baseVersionId,
  required String? lastPulledVersionId,
  DateTime? baseCommittedAt,
}) {
  if (remote.versionId == lastPulledVersionId) return false;
  return isFromElsewhere(
    remote,
    thisDeviceId: thisDeviceId,
    baseVersionId: baseVersionId,
    baseCommittedAt: baseCommittedAt,
  );
}
