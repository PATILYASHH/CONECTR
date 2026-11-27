import 'dart:convert';
import 'dart:typed_data';

import 'package:conectr/core/backup/backup_meta.dart';
import 'package:conectr/core/backup/backup_store.dart';
import 'package:conectr/core/backup/git_blob_sha.dart';
import 'package:conectr/core/google/drive_api.dart';
import 'package:conectr/core/google/drive_backup_store.dart';
import 'package:conectr/core/storage/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeDrive drive;
  late SecureStore store;
  late DriveBackupStore backups;

  BackupMeta meta(String device) => BackupMeta(
    deviceId: device,
    deviceName: device,
    backupModifiedAt: DateTime.utc(2026, 11, 27, 9),
    sourceFileName: '271126XPENCEBACKUP.json',
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'google_drive_email': 'me@gmail.com',
    });
    store = SecureStore();
    drive = _FakeDrive();
    backups = DriveBackupStore(
      drive,
      store,
      token: (email) async => email == 'me@gmail.com' ? 'token' : null,
      forgetToken: (_) async {},
    );
  });

  test('uploads into one tagged folder, and latest finds it', () async {
    await backups.ensureReady();
    final up = await backups.upload(
      utf8.encode('data'),
      meta('me'),
      replacing: null,
    );
    expect(drive.folders, hasLength(1));

    final latest = (await backups.latest())!;
    expect(latest.versionId, up.versionId);
    expect(latest.deviceId, 'me');
    expect(await backups.contentShaOf(latest), gitBlobSha(utf8.encode('data')));
    expect(utf8.decode((await backups.download(latest))!), 'data');
  });

  test('latest goes by tag across a duplicate folder', () async {
    await backups.ensureReady();
    await backups.upload([1], meta('me'), replacing: null);
    // Another phone raced to make its own folder and uploaded there.
    final other = drive.addFolder();
    drive.addBackup(other, meta('pixel'), [2]);
    expect((await backups.latest())!.deviceId, 'pixel');
  });

  test('a stale replace takes itself back out', () async {
    await backups.ensureReady();
    final first = await backups.upload([1], meta('me'), replacing: null);
    drive.addBackup(drive.folders.single, meta('pixel'), [2]);

    await expectLater(
      backups.upload([3], meta('me'), replacing: first),
      throwsA(isA<BackupConflictException>()),
    );
    expect(drive.backups, hasLength(2));
    expect((await backups.latest())!.deviceId, 'pixel');
  });

  test('two phones uploading at once both back off', () async {
    await backups.ensureReady();
    // The other phone's file lands between our upload and our check.
    drive.afterUpload = () =>
        drive.addBackup(drive.folders.single, meta('pixel'), [9]);
    await expectLater(
      backups.upload([1], meta('me'), replacing: null),
      throwsA(isA<BackupConflictException>()),
    );
    expect(drive.backups.single.appProperties['deviceId'], 'pixel');
  });

  test(
    'retention keeps the newest 30, the new upload always among them',
    () async {
      await backups.ensureReady();
      RemoteBackup? last;
      for (var i = 0; i < 33; i++) {
        last = await backups.upload([i], meta('me'), replacing: last);
      }
      expect(drive.backups, hasLength(DriveBackupStore.keep));
      expect(drive.backups.map((f) => f.id), contains(last!.versionId));
    },
  );

  test('a file without tags is a backup without metadata', () async {
    await backups.ensureReady();
    drive.addBackup(drive.folders.single, null, [1]);
    final latest = (await backups.latest())!;
    expect(latest.meta, isNull);
  });

  test('a trashed folder is replaced on the next upload', () async {
    await backups.ensureReady();
    drive.trashed.add(drive.folders.single);
    await backups.ensureReady();
    expect(drive.folders, hasLength(2));
    expect(await store.getDriveFolderId(), drive.folders.last);
  });

  test('without Drive access it asks to reconnect', () async {
    await store.setDriveEmail('someone@else.com');
    await expectLater(
      backups.latest(),
      throwsA(isA<DriveNotAuthorizedException>()),
    );
    expect(await backups.accessWorks(), isFalse);
  });
}

class _FakeDrive implements DriveApi {
  final folders = <String>[];
  final trashed = <String>{};
  final backups = <DriveFile>[];
  final _content = <String, List<int>>{};
  final _parents = <String, String>{};
  var _clock = DateTime.utc(2026, 11, 27);
  var _ids = 0;
  void Function()? afterUpload;

  DriveFile _file(Map<String, String>? props) {
    _clock = _clock.add(const Duration(seconds: 1));
    return DriveFile.fromJson({
      'id': 'f${_ids++}',
      'createdTime': _clock.toIso8601String(),
      'appProperties': ?props,
    });
  }

  String addFolder() {
    final id = 'folder${_ids++}';
    folders.add(id);
    return id;
  }

  void addBackup(String folder, BackupMeta? meta, List<int> bytes) {
    final props = meta == null
        ? {'connector': 'backup'}
        : DriveBackupStore.appPropertiesOf(meta, gitBlobSha(bytes));
    final file = _file(props);
    backups.add(file);
    _content[file.id] = bytes;
    _parents[file.id] = folder;
  }

  @override
  Future<String?> findFolder(String token, String tag) async =>
      folders.where((f) => !trashed.contains(f)).firstOrNull;

  @override
  Future<String> createFolder(String token, String name, String tag) async =>
      addFolder();

  @override
  Future<DriveFile?> getFile(String token, String id) async {
    if (folders.contains(id)) {
      return DriveFile.fromJson({'id': id, 'trashed': trashed.contains(id)});
    }
    return backups.where((f) => f.id == id).firstOrNull;
  }

  @override
  Future<List<DriveFile>> listTagged(
    String token,
    String tag, {
    DateTime? createdAfter,
    int pageSize = 100,
    bool firstPageOnly = false,
  }) async {
    final newestFirst = backups.reversed
        .where(
          (f) => createdAfter == null || f.createdTime!.isAfter(createdAfter),
        )
        .toList();
    return firstPageOnly ? newestFirst.take(pageSize).toList() : newestFirst;
  }

  @override
  Future<DriveFile> upload(
    String token, {
    required String name,
    required String parentId,
    required Map<String, String> appProperties,
    required List<int> bytes,
  }) async {
    final file = _file(appProperties);
    backups.add(file);
    _content[file.id] = bytes;
    _parents[file.id] = parentId;
    final hook = afterUpload;
    afterUpload = null;
    hook?.call();
    return file;
  }

  @override
  Future<Uint8List?> download(String token, String id) async {
    final bytes = _content[id];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String token, String id) async {
    backups.removeWhere((f) => f.id == id);
    _content.remove(id);
  }
}
