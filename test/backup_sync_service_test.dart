import 'dart:convert';
import 'dart:typed_data';

import 'package:conectr/core/backup/backup_folder_service.dart';
import 'package:conectr/core/backup/backup_meta.dart';
import 'package:conectr/core/backup/backup_sync_service.dart';
import 'package:conectr/core/backup/git_blob_sha.dart';
import 'package:conectr/core/config/app_config.dart';
import 'package:conectr/core/device/device_identity.dart';
import 'package:conectr/core/github/github_api.dart';
import 'package:conectr/core/storage/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf_util/saf_util_platform_interface.dart' show SafDocumentFile;

/// The whole stale-phone story from the sync review, through the real
/// service: GitHub and the folder are fakes, the rules and state are not.
void main() {
  late _FakeGithub github;
  late _FakeFolder folder;
  late BackupSyncService service;
  late SecureStore store;

  final now = DateTime.now().toUtc();
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'github_provider_token': 'token',
      'github_login': 'yash',
      'backup_folder_uri': 'tree',
    });
    github = _FakeGithub();
    folder = _FakeFolder();
    store = SecureStore();
    service = BackupSyncService(
      github: github,
      folder: folder,
      store: store,
      device: _FakeDevice('me'),
    );
  });

  test('a stale phone never replaces the other phone\'s backup — before or '
      'after importing it', () async {
    github.pushFrom('pixel', ago(120), 'pixel data');
    // XPENC's auto-backup, as the user opens it to import: a fresh file of
    // this phone's old data, newer by time than the Pixel's.
    folder.xpencBackup(ago(60), 'old data');

    expect(await service.upload(), isA<RemoteNotImported>());
    expect(await service.upload(manual: true), isA<RemoteNotImported>());
    expect(github.head, 'pixel data');

    final pulled = await service.pull();
    expect(pulled, isA<Pulled>());
    expect(folder.content(AppConfig.backupFileName), 'pixel data');
    final pending = (await service.state()).pendingImport!;

    await service.confirmImported(pending.commitSha);
    expect((await service.state()).pendingImport, isNull);
    // Still the file written before the import.
    expect(await service.upload(manual: true), isA<UploadNotNeeded>());
    expect(github.head, 'pixel data');

    // XPENC's next backup holds the imported data plus whatever's new.
    folder.xpencBackup(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
      'pixel data + new',
    );
    expect(await service.upload(), isA<Uploaded>());
    expect(github.head, 'pixel data + new');
    expect(github.commits, hasLength(2));
  });

  group('XPENC\'s "Tell Connector" link', () {
    // What XPENC sends: the git blob sha of the file it imported, which is
    // the file Connector saved — byte for byte — when the import is real.
    String fingerprint(String content) => gitBlobSha(utf8.encode(content));

    test('confirms the import when XPENC imported the pulled file', () async {
      github.pushFrom('pixel', ago(120), 'pixel data');
      folder.xpencBackup(ago(60), 'old data');
      await service.pull();
      final pending = (await service.state()).pendingImport!;

      expect(
        await service.confirmImportedFile(fingerprint('pixel data')),
        ImportHandoff.confirmed,
      );
      final state = await service.state();
      expect(state.pendingImport, isNull);
      expect(state.pendingImportSha, isNull);
      expect(state.baseCommitSha, pending.commitSha);
      // Exactly like the button: the pre-import file never goes up.
      expect(await service.upload(manual: true), isA<UploadNotNeeded>());
    });

    test('refuses a different file, and changes nothing', () async {
      github.pushFrom('pixel', ago(120), 'pixel data');
      folder.xpencBackup(ago(60), 'old data');
      await service.pull();

      expect(
        await service.confirmImportedFile(fingerprint('some other backup')),
        ImportHandoff.differentFile,
      );
      expect((await service.state()).pendingImport, isNotNull);
      expect(await service.upload(manual: true), isA<RemoteNotImported>());
    });

    test('with nothing pulled, there is nothing to confirm', () async {
      expect(
        await service.confirmImportedFile(fingerprint('pixel data')),
        ImportHandoff.nothingPending,
      );
    });
  });

  test('"Keep this phone\'s instead" replaces it, and clears the pulled '
      'file', () async {
    github.pushFrom('pixel', ago(120), 'pixel data');
    folder.xpencBackup(ago(60), 'this phone\'s data');
    await service.pull();

    expect(
      await service.upload(manual: true, overwriteNewer: true),
      isA<Uploaded>(),
    );
    expect(github.head, 'this phone\'s data');
    final state = await service.state();
    expect(state.pendingImport, isNull);
    expect(state.baseCommitSha, github.commits.last.sha);
    // And it's this phone's to replace from then on.
    folder.xpencBackup(ago(1), 'later');
    expect(await service.upload(), isA<Uploaded>());
  });

  test('a push from another phone between the check and the write is '
      'refused, not overwritten', () async {
    folder.xpencBackup(ago(60), 'mine');
    expect(await service.upload(), isA<Uploaded>());

    folder.xpencBackup(ago(30), 'mine, newer');
    github.beforePut = () => github.pushFrom('pixel', ago(1), 'pixel data');
    await expectLater(
      service.upload(),
      throwsA(isA<GithubConflictException>()),
    );
    expect(github.head, 'pixel data');

    // The next run sees the Pixel's backup and waits for an import.
    github.beforePut = null;
    expect(await service.upload(manual: true), isA<RemoteNotImported>());
  });

  test('one phone on its own just keeps uploading', () async {
    folder.xpencBackup(ago(60), 'monday');
    expect(await service.upload(), isA<Uploaded>());
    expect(await service.upload(), isA<UploadNotNeeded>());
    expect(await service.pull(), isA<PullNotNeeded>());

    folder.xpencBackup(ago(10), 'tuesday');
    expect(await service.upload(), isA<Uploaded>());
    expect(github.head, 'tuesday');
  });
}

class _Commit {
  _Commit(this.sha, this.message, this.date, this.bytes);

  final String sha;
  final String message;
  final DateTime date;
  final List<int> bytes;
}

class _FakeGithub implements GithubApi {
  final commits = <_Commit>[];

  /// Runs just before a write lands — to slip another phone's push in.
  void Function()? beforePut;

  String? get head => commits.isEmpty ? null : utf8.decode(commits.last.bytes);

  void pushFrom(String deviceId, DateTime modified, String content) {
    final meta = BackupMeta(
      deviceId: deviceId,
      deviceName: deviceId,
      backupModifiedAt: modified,
      sourceFileName: '241026XPENCEBACKUP.json',
    );
    _commit(meta.toCommitMessage(), utf8.encode(content));
  }

  String _commit(String message, List<int> bytes) {
    final sha = 'commit${commits.length}';
    commits.add(_Commit(sha, message, DateTime.now().toUtc(), bytes));
    return sha;
  }

  _Commit? _at(String? ref) => ref == null
      ? (commits.isEmpty ? null : commits.last)
      : commits.where((c) => c.sha == ref).firstOrNull;

  @override
  Future<String> getAuthenticatedLogin(String token) async => 'yash';

  @override
  Future<bool> repoExists(String token, String owner, String repo) async =>
      true;

  @override
  Future<void> createPrivateRepo(
    String token,
    String repoName, {
    String description = '',
  }) async {}

  @override
  Future<GithubCommit?> getLatestCommit(
    String token,
    String owner,
    String repo,
    String path,
  ) async {
    final c = _at(null);
    return c == null
        ? null
        : GithubCommit(sha: c.sha, message: c.message, date: c.date);
  }

  @override
  Future<GithubFile?> getFile(
    String token,
    String owner,
    String repo,
    String path, {
    String? ref,
  }) async {
    final c = _at(ref);
    return c == null
        ? null
        : GithubFile(
            sha: gitBlobSha(c.bytes),
            contentBytes: Uint8List.fromList(c.bytes),
          );
  }

  @override
  Future<String?> getFileSha(
    String token,
    String owner,
    String repo,
    String path, {
    required String ref,
  }) async {
    final c = _at(ref);
    return c == null ? null : gitBlobSha(c.bytes);
  }

  @override
  Future<String> putFile(
    String token,
    String owner,
    String repo,
    String path, {
    required List<int> contentBytes,
    required String commitMessage,
    String? existingSha,
  }) async {
    beforePut?.call();
    final current = _at(null);
    if (existingSha != (current == null ? null : gitBlobSha(current.bytes))) {
      throw GithubConflictException(409, 'does not match');
    }
    return _commit(commitMessage, contentBytes);
  }
}

class _FakeFolder implements BackupFolderService {
  final _files = <String, (DateTime, List<int>)>{};

  /// XPENC writing its backup; same-day backups share a name.
  void xpencBackup(DateTime modified, String content) =>
      _files['241026XPENCEBACKUP.json'] = (modified, utf8.encode(content));

  String? content(String name) {
    final file = _files[name];
    return file == null ? null : utf8.decode(file.$2);
  }

  @override
  Future<String?> pickBackupFolder() async => 'tree';

  @override
  Future<bool> hasAccess(String treeUri) async => true;

  @override
  Future<SafDocumentFile?> findLatestBackupFile(String treeUri) async {
    final xpenc = _files.entries
        .where((e) => e.key.endsWith('XPENCEBACKUP.json'))
        .toList();
    if (xpenc.isEmpty) return null;
    final e = xpenc.first;
    return SafDocumentFile(
      uri: e.key,
      name: e.key,
      isDir: false,
      length: e.value.$2.length,
      lastModified: e.value.$1.millisecondsSinceEpoch,
    );
  }

  @override
  Future<Uint8List> readFile(String fileUri) async =>
      Uint8List.fromList(_files[fileUri]!.$2);

  @override
  Future<void> writeRestoredBackup(
    String treeUri,
    String fileName,
    Uint8List bytes,
  ) async {
    _files[fileName] = (DateTime.now().toUtc(), bytes);
  }
}

class _FakeDevice implements DeviceIdentity {
  _FakeDevice(this._id);

  final String _id;

  @override
  Future<String> id() async => _id;

  @override
  Future<String> name() async => 'Galaxy S23';

  @override
  Future<String> defaultName() async => 'Galaxy S23';

  @override
  Future<void> rename(String name) async {}
}
