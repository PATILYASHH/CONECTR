import 'package:conectr/core/backup/backup_meta.dart';
import 'package:conectr/core/backup/sync_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);

  RemoteBackup remoteFrom(String? deviceId, DateTime at, {String sha = 'c9'}) {
    return RemoteBackup(
      commitSha: sha,
      committedAt: at,
      meta: deviceId == null
          ? null
          : BackupMeta(
              deviceId: deviceId,
              deviceName: 'Pixel 7',
              backupModifiedAt: at,
              sourceFileName: '241026XPENCEBACKUP.json',
            ),
    );
  }

  group('isAutoBackupDue', () {
    test('never when off', () {
      expect(isAutoBackupDue(AutoBackup.off, null, now), isFalse);
    });

    test('on every run after each XPENC backup', () {
      expect(isAutoBackupDue(AutoBackup.afterXpencBackup, now, now), isTrue);
    });

    test('daily: first run, then only once 24h have passed', () {
      expect(isAutoBackupDue(AutoBackup.daily, null, now), isTrue);
      final ago = now.subtract(const Duration(hours: 23));
      expect(isAutoBackupDue(AutoBackup.daily, ago, now), isFalse);
      final dayAgo = now.subtract(const Duration(hours: 24));
      expect(isAutoBackupDue(AutoBackup.daily, dayAgo, now), isTrue);
    });

    test('weekly: only once 7 days have passed', () {
      final sixDays = now.subtract(const Duration(days: 6));
      expect(isAutoBackupDue(AutoBackup.weekly, sixDays, now), isFalse);
      final week = now.subtract(const Duration(days: 7));
      expect(isAutoBackupDue(AutoBackup.weekly, week, now), isTrue);
    });
  });

  group('isPullCheckDue', () {
    test('on the first run', () {
      expect(isPullCheckDue(null, now), isTrue);
    });

    test('not again within the hour, allowing for scheduler jitter', () {
      final recent = now.subtract(const Duration(minutes: 49));
      expect(isPullCheckDue(recent, now), isFalse);
      final hourish = now.subtract(const Duration(minutes: 50));
      expect(isPullCheckDue(hourish, now), isTrue);
    });
  });

  group('isFromElsewhere', () {
    final at = DateTime.utc(2026, 10, 24, 10);

    test('another phone\'s backup this phone hasn\'t imported', () {
      expect(
        isFromElsewhere(
          remoteFrom('other', at),
          thisDeviceId: 'me',
          baseCommitSha: null,
        ),
        isTrue,
      );
    });

    test('not once this phone confirmed importing that very commit', () {
      expect(
        isFromElsewhere(
          remoteFrom('other', at),
          thisDeviceId: 'me',
          baseCommitSha: 'c9',
        ),
        isFalse,
      );
    });

    test('not this phone\'s own upload', () {
      expect(
        isFromElsewhere(
          remoteFrom('me', at),
          thisDeviceId: 'me',
          baseCommitSha: null,
        ),
        isFalse,
      );
    });

    test('a commit with no metadata (made by hand) counts as elsewhere', () {
      expect(
        isFromElsewhere(
          remoteFrom(null, at),
          thisDeviceId: 'me',
          baseCommitSha: null,
        ),
        isTrue,
      );
    });
  });

  group('uploadVerdict (upload rule)', () {
    final local = DateTime.utc(2026, 10, 24, 9, 40);

    UploadVerdict verdict(
      RemoteBackup? remote, {
      DateTime? localModified,
      DateTime? handledUpTo,
      String? baseCommitSha,
    }) {
      return uploadVerdict(
        localModified ?? local,
        remote: remote,
        handledUpTo: handledUpTo,
        thisDeviceId: 'me',
        baseCommitSha: baseCommitSha,
      );
    }

    test('uploads when GitHub has nothing yet', () {
      expect(verdict(null), UploadVerdict.upload);
    });

    test('uploads a newer backup over this phone\'s own', () {
      expect(
        verdict(remoteFrom('me', DateTime.utc(2026, 10, 24, 9))),
        UploadVerdict.upload,
      );
    });

    test('never replaces this phone\'s own newer or identical upload', () {
      expect(verdict(remoteFrom('me', local)), UploadVerdict.upToDate);
      expect(
        verdict(remoteFrom('me', DateTime.utc(2026, 10, 24, 10))),
        UploadVerdict.upToDate,
      );
    });

    test('a stale phone\'s brand-new file never replaces another phone\'s '
        'backup', () {
      // XPENC's auto-backup on open: written at 12:00, holding week-old
      // data — far "newer" by time than the other phone's 10:00 backup.
      expect(
        verdict(
          remoteFrom('other', DateTime.utc(2026, 10, 24, 10)),
          localModified: now,
        ),
        UploadVerdict.notImported,
      );
    });

    test('nor a hand-made commit', () {
      expect(
        verdict(remoteFrom(null, DateTime.utc(2026, 10, 24, 9))),
        UploadVerdict.notImported,
      );
    });

    test('after confirming the import, only backups written since go up', () {
      final importedAt = DateTime.utc(2026, 10, 24, 12, 30);
      final remote = remoteFrom('other', DateTime.utc(2026, 10, 24, 10));
      // Written before the import — built on the old data.
      expect(
        verdict(
          remote,
          localModified: now,
          handledUpTo: importedAt,
          baseCommitSha: 'c9',
        ),
        UploadVerdict.upToDate,
      );
      expect(
        verdict(
          remote,
          localModified: importedAt.add(const Duration(minutes: 5)),
          handledUpTo: importedAt,
          baseCommitSha: 'c9',
        ),
        UploadVerdict.upload,
      );
    });

    test('the imported backup\'s time never blocks — other phone\'s clock', () {
      // The other phone's clock ran an hour fast: its backup claims a time
      // after this phone's next one. Still this phone's to replace.
      final imported = remoteFrom('other', DateTime.utc(2026, 10, 24, 14));
      expect(
        verdict(
          imported,
          localModified: now,
          handledUpTo: DateTime.utc(2026, 10, 24, 11),
          baseCommitSha: 'c9',
        ),
        UploadVerdict.upload,
      );
    });
  });

  group('shouldPull', () {
    final remoteTime = DateTime.utc(2026, 10, 24, 10);

    bool pull(
      RemoteBackup remote, {
      String? baseCommitSha,
      String? lastPulledCommitSha,
    }) {
      return shouldPull(
        remote,
        thisDeviceId: 'me',
        baseCommitSha: baseCommitSha,
        lastPulledCommitSha: lastPulledCommitSha,
      );
    }

    test('pulls another phone\'s backup', () {
      expect(pull(remoteFrom('other', remoteTime)), isTrue);
    });

    test('never pulls back this phone\'s own upload', () {
      expect(pull(remoteFrom('me', remoteTime)), isFalse);
    });

    test('skips a commit it already pulled', () {
      expect(
        pull(remoteFrom('other', remoteTime), lastPulledCommitSha: 'c9'),
        isFalse,
      );
    });

    test('skips the commit this phone already imported', () {
      expect(
        pull(remoteFrom('other', remoteTime), baseCommitSha: 'c9'),
        isFalse,
      );
    });
  });
}
