import 'package:conectr/core/backup/backup_meta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final meta = BackupMeta(
    deviceId: 'a1b2c3',
    deviceName: 'Pixel 7',
    backupModifiedAt: DateTime.utc(2026, 10, 24, 9, 38, 12, 345),
    sourceFileName: '241026XPENCEBACKUP.json',
  );

  group('BackupMeta commit message', () {
    test('round-trips through the commit message', () {
      final parsed = BackupMeta.parse(meta.toCommitMessage())!;
      expect(parsed.deviceId, meta.deviceId);
      expect(parsed.deviceName, meta.deviceName);
      expect(parsed.backupModifiedAt, meta.backupModifiedAt);
      expect(parsed.sourceFileName, meta.sourceFileName);
    });

    test('the summary line names the phone and the file', () {
      expect(
        meta.toCommitMessage().split('\n').first,
        'Backup from Pixel 7 — 241026XPENCEBACKUP.json',
      );
    });

    test('a commit from before metadata existed parses to null', () {
      expect(
        BackupMeta.parse('Backup from Connector — 241026XPENCEBACKUP.json'),
        isNull,
      );
    });

    test('a commit with an unreadable time parses to null', () {
      final broken = meta.toCommitMessage().replaceAll(
        RegExp(r'Backup-Modified: .*'),
        'Backup-Modified: x',
      );
      expect(BackupMeta.parse(broken), isNull);
    });
  });

  group('BackupMeta.cleanDeviceName', () {
    test('collapses whitespace so a name can never break the message', () {
      expect(
        BackupMeta.cleanDeviceName('  My\nGalaxy   S23 '),
        'My Galaxy S23',
      );
    });

    test('caps the length', () {
      expect(BackupMeta.cleanDeviceName('x' * 60).length, 40);
    });

    test('falls back to a generic name when empty', () {
      expect(BackupMeta.cleanDeviceName('   '), 'Android phone');
    });
  });

  group('RemoteBackup', () {
    final committedAt = DateTime.utc(2026, 10, 24, 10);

    test('uses the backup time from the metadata when present', () {
      final remote = RemoteBackup(
        commitSha: 'c1',
        committedAt: committedAt,
        meta: meta,
      );
      expect(remote.backupModifiedAt, meta.backupModifiedAt);
    });

    test('falls back to the commit time for an old-style commit', () {
      final remote = RemoteBackup(commitSha: 'c1', committedAt: committedAt);
      expect(remote.backupModifiedAt, committedAt);
      expect(remote.deviceId, isNull);
    });
  });
}
