import 'dart:convert';
import 'dart:typed_data';

import 'package:conectr/core/backup/backup_meta.dart';
import 'package:conectr/core/backup/backup_store.dart';
import 'package:conectr/core/backup/git_blob_sha.dart';
import 'package:conectr/core/exocloud/exocloud_api.dart';
import 'package:conectr/core/exocloud/exocloud_backup_store.dart';
import 'package:conectr/core/exocloud/exocloud_crypto.dart';
import 'package:conectr/core/shared/session_tokens.dart';
import 'package:conectr/core/storage/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExoCloudCrypto', () {
    test('round-trips, and a different key or a flipped bit fails', () async {
      final key = ExoCloudCrypto.newKey();
      final plain = utf8.encode('{"entries": [1, 2, 3]}');
      final sealed = await ExoCloudCrypto.encrypt(plain, key);

      expect(utf8.decode(sealed.sublist(0, 4)), 'EXC1');
      expect(await ExoCloudCrypto.decrypt(sealed, key), plain);
      await expectLater(
        ExoCloudCrypto.decrypt(sealed, ExoCloudCrypto.newKey()),
        throwsA(isA<ExoCloudDecryptException>()),
      );
      final tampered = Uint8List.fromList(sealed)..[20] ^= 1;
      await expectLater(
        ExoCloudCrypto.decrypt(tampered, key),
        throwsA(isA<ExoCloudDecryptException>()),
      );
    });

    test('two encryptions of the same backup differ (fresh nonce)', () async {
      final key = ExoCloudCrypto.newKey();
      final a = await ExoCloudCrypto.encrypt([1, 2, 3], key);
      final b = await ExoCloudCrypto.encrypt([1, 2, 3], key);
      expect(a, isNot(b));
    });

    test('the recovery key round-trips and forgives how it is typed', () {
      final key = ExoCloudCrypto.newKey();
      final recovery = ExoCloudCrypto.toRecoveryKey(key);
      expect(recovery.replaceAll('-', ''), hasLength(52));
      expect(ExoCloudCrypto.fromRecoveryKey(recovery), key);
      final sloppy = recovery.toLowerCase().replaceAll('-', ' ');
      expect(ExoCloudCrypto.fromRecoveryKey(sloppy), key);
    });

    test('a short or garbled recovery key is refused', () {
      expect(
        () => ExoCloudCrypto.fromRecoveryKey('ABCD-EFGH'),
        throwsA(isA<BadRecoveryKeyException>()),
      );
      final bad = '${'0' * 51}U';
      expect(
        () => ExoCloudCrypto.fromRecoveryKey(bad),
        throwsA(isA<BadRecoveryKeyException>()),
      );
    });

    test('the key check matches only its own key', () async {
      final key = ExoCloudCrypto.newKey();
      expect(
        await ExoCloudCrypto.keyCheck(key),
        await ExoCloudCrypto.keyCheck(List.of(key)),
      );
      expect(
        await ExoCloudCrypto.keyCheck(key),
        isNot(await ExoCloudCrypto.keyCheck(ExoCloudCrypto.newKey())),
      );
    });
  });

  group('ExoCloudBackupStore', () {
    late _FakeExoCloud api;
    late SecureStore store;
    late ExoCloudBackupStore exo;
    late List<int> key;

    BackupMeta meta(String device) => BackupMeta(
      deviceId: device,
      deviceName: device,
      backupModifiedAt: DateTime.utc(2026, 11, 27, 9),
      sourceFileName: '271126XPENCEBACKUP.json',
    );

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      store = SecureStore();
      key = ExoCloudCrypto.newKey();
      await store.setExoCloudKey(key);
      api = _FakeExoCloud();
      exo = ExoCloudBackupStore(
        api,
        store,
        token: () async => const HaveToken('token', 'user-1'),
      );
    });

    test('uploads only ciphertext, and downloads the plaintext', () async {
      final plain = utf8.encode('my money');
      final up = await exo.upload(plain, meta('me'), replacing: null);

      final stored = api.objects.values.single;
      expect(
        utf8.decode(stored, allowMalformed: true),
        isNot(contains('money')),
      );
      expect(api.objects.keys.single, startsWith('user-1/'));
      expect(await exo.contentShaOf(up), gitBlobSha(plain));

      final latest = (await exo.latest())!;
      expect(latest.versionId, up.versionId);
      expect(latest.deviceId, 'me');
      expect(await exo.download(latest), plain);
    });

    test('a stale replace is refused, and its object taken back out', () async {
      final first = await exo.upload([1], meta('me'), replacing: null);
      await exo.upload([2], meta('pixel'), replacing: first);

      await expectLater(
        exo.upload([3], meta('me'), replacing: first),
        throwsA(isA<BackupConflictException>()),
      );
      expect(api.rows, hasLength(2));
      expect(api.objects, hasLength(2));
    });

    test('retention leftovers are deleted from storage', () async {
      RemoteBackup? last;
      for (var i = 0; i < 12; i++) {
        last = await exo.upload([i], meta('me'), replacing: last);
      }
      expect(api.rows, hasLength(10));
      expect(api.objects, hasLength(10));
    });

    test('without the key on this phone it says what to do', () async {
      await store.setExoCloudKey(null);
      expect(await exo.isConnected(), isFalse);
      await expectLater(
        exo.upload([1], meta('me'), replacing: null),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('recovery key'),
          ),
        ),
      );
    });
  });
}

/// exocloud_commit's rules, in memory.
class _FakeExoCloud implements ExoCloudApi {
  final objects = <String, List<int>>{};
  final rows = <Map<String, dynamic>>[];
  var _clock = DateTime.utc(2026, 11, 27);

  @override
  Future<ExoCloudRow?> row(String token, {String? id}) async {
    final found = id == null
        ? (rows.isEmpty ? null : rows.last)
        : rows.where((r) => r['id'] == id).firstOrNull;
    return found == null ? null : ExoCloudRow.fromJson(found);
  }

  @override
  Future<void> uploadObject(String token, String path, List<int> bytes) async {
    objects[path] = bytes;
  }

  @override
  Future<Uint8List?> downloadObject(String token, String path) async {
    final bytes = objects[path];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteObjects(String token, List<String> paths) async {
    paths.forEach(objects.remove);
  }

  @override
  Future<({ExoCloudRow backup, List<String> removed})> commit(
    String token, {
    required String objectPath,
    required String? replacingId,
    required int sizeBytes,
    required String deviceId,
    required String deviceName,
    required DateTime backupModifiedAt,
    required String sourceFile,
    required String contentSha,
  }) async {
    final latest = rows.isEmpty ? null : rows.last['id'];
    if (latest != replacingId) throw const BackupConflictException();
    _clock = _clock.add(const Duration(minutes: 1));
    final row = {
      'id': 'row${rows.length}-${_clock.millisecondsSinceEpoch}',
      'object_path': objectPath,
      'created_at': _clock.toIso8601String(),
      'device_id': deviceId,
      'device_name': deviceName,
      'backup_modified_at': backupModifiedAt.toIso8601String(),
      'source_file': sourceFile,
      'content_sha': contentSha,
    };
    rows.add(row);
    final removed = <String>[];
    while (rows.length > 10) {
      removed.add(rows.removeAt(0)['object_path'] as String);
    }
    return (backup: ExoCloudRow.fromJson(row), removed: removed);
  }
}
