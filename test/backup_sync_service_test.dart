import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conectr/core/backup/backup_folder_service.dart';
import 'package:conectr/core/backup/backup_meta.dart';
import 'package:conectr/core/backup/backup_sync_service.dart';
import 'package:conectr/core/backup/git_blob_sha.dart';
import 'package:conectr/core/config/app_config.dart';
import 'package:conectr/core/device/device_identity.dart';
import 'package:conectr/core/github/github_api.dart';
import 'package:conectr/core/github/github_backup_store.dart';
import 'package:conectr/core/storage/secure_store.dart';
import 'package:conectr/core/xpenc/xpenc_inbox.dart';
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
      backups: GithubBackupStore(github, store),
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

    await service.confirmImported(pending.versionId);
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
      expect(state.baseVersionId, pending.versionId);
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
    expect(state.baseVersionId, github.commits.last.sha);
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

  group('XPENC takes the pulled backup in by itself', () {
    late Directory root;
    late FileXpencInbox inbox;

    String sha(String content) => gitBlobSha(utf8.encode(content));
    Map<String, dynamic> inboxJson() =>
        jsonDecode(
              File(
                '${root.path}/xpenc/${FileXpencInbox.inboxFile}',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    File pendingFile() =>
        File('${root.path}/xpenc/${FileXpencInbox.pendingFile}');

    /// What `XpencProvider.confirmImport` writes.
    void xpencReports(String fileSha, DateTime at) {
      final dir = Directory('${root.path}/xpenc')..createSync(recursive: true);
      File('${dir.path}/${FileXpencInbox.importFile}').writeAsStringSync(
        jsonEncode({'sha': fileSha, 'at': at.millisecondsSinceEpoch}),
      );
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('conectr_inbox_');
      addTearDown(() => root.deleteSync(recursive: true));
      inbox = FileXpencInbox(() async => root);
      service = BackupSyncService(
        backups: GithubBackupStore(github, store),
        folder: folder,
        store: store,
        device: _FakeDevice('me'),
        inbox: inbox,
      );
    });

    test('an upload names the file this phone is built on', () async {
      folder.xpencBackup(ago(30), 'mine');
      await service.upload();
      expect(inboxJson()['baseFileSha'], sha('mine'));
      expect(inboxJson()['pending'], isNull);
    });

    test('a pull leaves the backup, and what it is, for XPENC', () async {
      github.pushFrom('pixel', ago(120), 'pixel data');
      await service.pull();

      final pending = inboxJson()['pending'] as Map<String, dynamic>;
      expect(pending['sha'], sha('pixel data'));
      expect(pending['deviceName'], 'pixel');
      expect(pendingFile().readAsStringSync(), 'pixel data');
    });

    test("XPENC's report confirms the import as of when it happened", () async {
      folder.xpencBackup(ago(90), 'mine');
      await service.upload();
      github.pushFrom('pixel', ago(60), 'pixel data');
      await service.pull();

      // XPENC took it in 20 minutes ago, then wrote a backup with new
      // entries — which must still go up.
      xpencReports(sha('pixel data'), ago(20));
      folder.xpencBackup(ago(10), 'pixel data + new');

      expect(await service.upload(), isA<Uploaded>());
      expect(github.head, 'pixel data + new');
      expect((await service.state()).pendingImport, isNull);
      expect(inboxJson()['baseFileSha'], sha('pixel data + new'));
      expect(pendingFile().existsSync(), isFalse);
    });

    test('the confirmed import is the base until the next upload', () async {
      github.pushFrom('pixel', ago(60), 'pixel data');
      await service.pull();
      xpencReports(sha('pixel data'), ago(5));

      await service.applyXpencImport();
      expect(inboxJson()['baseFileSha'], sha('pixel data'));
      expect(inboxJson()['pending'], isNull);
    });

    test('a report for some other file changes nothing', () async {
      github.pushFrom('pixel', ago(60), 'pixel data');
      await service.pull();
      xpencReports(sha('something else'), ago(5));

      await service.applyXpencImport();
      expect((await service.state()).pendingImport, isNotNull);
      expect(inboxJson()['pending'], isNotNull);
    });

    test('the import report is read once', () async {
      xpencReports('abc', ago(1));
      expect((await inbox.takeImport())?.sha, 'abc');
      expect(await inbox.takeImport(), isNull);
    });
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

  group('a 401 only means "Reconnect GitHub" once GitHub confirms it', () {
    test(
      'a one-off refusal of a good token is a glitch, not a revoke',
      () async {
        github.pushFrom('pixel', ago(120), 'pixel data');
        github.refuseNext = 1;
        await expectLater(
          service.pull(),
          throwsA(isA<GithubAuthGlitchException>()),
        );
        // Next run, all fine.
        expect(await service.pull(), isA<Pulled>());
      },
    );

    test('a token replaced mid-run is retried with the new one', () async {
      github.pushFrom('pixel', ago(120), 'pixel data');
      github.revoked.add('token');
      // Connected again in the app while this run was in flight.
      github.beforeRefusal = () => store.setGithubToken('fresh');
      expect(await service.pull(), isA<Pulled>());
    });

    test('a revoked token still says so', () async {
      github.pushFrom('pixel', ago(120), 'pixel data');
      github.revoked.add('token');
      await expectLater(
        service.pull(),
        throwsA(
          isA<GithubApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('opening the app clears a "reconnect" that no longer holds', () async {
      await store.updateSyncState((s) {
        s.problem = 'GitHub access was revoked or has expired.';
        s.problemNeedsReconnect = true;
      });
      await service.recheckAccess();
      expect((await service.state()).problem, isNull);

      github.revoked.add('token');
      await store.updateSyncState((s) {
        s.problem = 'GitHub access was revoked or has expired.';
        s.problemNeedsReconnect = true;
      });
      await service.recheckAccess();
      expect((await service.state()).problemNeedsReconnect, isTrue);
    });
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

  /// Tokens GitHub refuses outright, and requests it refuses once (401)
  /// although the token is fine.
  final revoked = <String>{};
  int refuseNext = 0;

  /// Runs as a refusal is about to happen — to swap the token meanwhile.
  Future<void> Function()? beforeRefusal;

  Future<void> _authCheck(String token) async {
    if (revoked.contains(token)) {
      final hook = beforeRefusal;
      beforeRefusal = null;
      await hook?.call();
      throw GithubApiException(401, 'Bad credentials');
    }
    if (refuseNext > 0) {
      refuseNext--;
      throw GithubApiException(401, 'Bad credentials');
    }
  }

  @override
  Future<bool> tokenWorks(String token) async => !revoked.contains(token);

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
    await _authCheck(token);
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
  Future<GithubCommit> putFile(
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
    final sha = _commit(commitMessage, contentBytes);
    final c = _at(sha)!;
    return GithubCommit(sha: c.sha, message: c.message, date: c.date);
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
