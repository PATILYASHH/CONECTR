import 'dart:convert';
import 'dart:io';

import 'package:conectr/core/profile/profile_repository.dart';
import 'package:conectr/core/shared/session_tokens.dart';
import 'package:conectr/core/shared/shared_api.dart';
import 'package:conectr/core/shared/shared_entry.dart';
import 'package:conectr/core/shared/shared_files.dart';
import 'package:conectr/core/shared/shared_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sync round through real files: the server is a fake, the outbox,
/// snapshot and failure records are not.
void main() {
  late Directory root;
  late SharedFiles files;
  late _FakeApi api;
  late List<String> announced;
  TokenResult token = const HaveToken('access', 'me');

  SharedSync sync() => SharedSync(
    api: api,
    files: files,
    tokens: () async => token,
    announce: (entry, from) async => announced.add('${entry.id}@$from'),
  );

  Future<void> queue(String name, Map<String, dynamic> op) async {
    final dir = Directory('${root.path}/xpenc/outbox')
      ..createSync(recursive: true);
    await File('${dir.path}/$name.json').writeAsString(jsonEncode(op));
  }

  Future<Map<String, dynamic>> snapshot() async =>
      jsonDecode(await File('${root.path}/xpenc/shared.json').readAsString())
          as Map<String, dynamic>;

  Map<String, dynamic> add(String opId, String ref) => {
    'opId': opId,
    'type': 'add',
    'clientRef': ref,
    'friendId': 'ana',
    'theyOwe': true,
    'amountMinor': 50000,
    'currency': 'INR',
    'date': '2026-11-05',
  };

  setUp(() {
    root = Directory.systemTemp.createTempSync('shared_sync');
    files = SharedFiles(() async => root);
    api = _FakeApi();
    announced = [];
    token = const HaveToken('access', 'me');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('sends what XPENC queued in order, then leaves the result for it',
      () async {
    await queue('0001-a', add('op-0001-add', 'ref-dinner'));
    await queue('0002-b', {
      'opId': 'op-0002-edit',
      'type': 'edit',
      'clientRef': 'ref-dinner',
      'theyOwe': true,
      'amountMinor': 60000,
      'currency': 'INR',
      'date': '2026-11-05',
    });

    expect(await sync().run(), SharedSyncOutcome.synced);

    expect(api.applied, ['add ref-dinner', 'edit ref-dinner']);
    expect(await files.outbox(), isEmpty);
    final shared = await snapshot();
    expect(shared['signedIn'], isTrue);
    expect(shared['me'], 'me');
    final entry = (shared['entries'] as List).single as Map<String, dynamic>;
    expect(entry['friendId'], 'ana');
    expect(entry['byMe'], isTrue);
    expect(entry['clientRef'], 'ref-dinner');
    expect(entry['theyOwe'], isTrue);
    expect(entry['amountMinor'], 60000);
    expect(entry['status'], 'pending');
  });

  test('stops at the first op that may work later, so nothing overtakes it',
      () async {
    await queue('0001-a', add('op-0001-add', 'ref-dinner'));
    await queue('0002-b', add('op-0002-add', 'ref-taxi'));
    api.failNext = SharedApiException(503, 'unavailable');

    expect(await sync().run(), SharedSyncOutcome.unavailable);
    expect((await files.outbox()).length, 2);

    expect(await sync().run(), SharedSyncOutcome.synced);
    expect(api.applied, ['add ref-dinner', 'add ref-taxi']);
  });

  test('a refused op is set aside with its reason, and the rest goes on',
      () async {
    await queue('0001-a', add('op-0001-add', 'ref-dinner'));
    await queue('0002-b', add('op-0002-add', 'ref-taxi'));
    api.failNext = SharedApiException(400, 'not_friends');

    expect(await sync().run(), SharedSyncOutcome.synced);

    expect(api.applied, ['add ref-taxi']);
    final failed = (await snapshot())['failed'] as List;
    expect(failed.single, containsPair('clientRef', 'ref-dinner'));
    expect(failed.single, containsPair('error', 'not_friends'));
  });

  test('a friend\'s new entry is announced once, and again once edited',
      () async {
    api.rows.add(_row('e1', createdBy: 'ana', version: 1));

    await sync().run();
    await sync().run();
    expect(announced, ['e1@ana']);

    api.rows[0] = _row('e1', createdBy: 'ana', version: 2);
    await sync().run();
    expect(announced, ['e1@ana', 'e1@ana']);
  });

  test('signed out: XPENC hears so, and nothing queued goes out later',
      () async {
    await queue('0001-a', add('op-0001-add', 'ref-dinner'));
    token = const SignedOut();

    expect(await sync().run(), SharedSyncOutcome.signedOut);

    expect(await files.outbox(), isEmpty);
    final shared = await snapshot();
    expect(shared['signedIn'], isFalse);
    expect((shared['failed'] as List).single, containsPair('error', 'signed_out'));
  });

  test('offline: the outbox waits and the last snapshot stays', () async {
    await sync().run();
    await queue('0001-a', add('op-0001-add', 'ref-dinner'));
    token = const TokenUnavailable();

    expect(await sync().run(), SharedSyncOutcome.unavailable);
    expect((await files.outbox()).length, 1);
    expect((await snapshot())['signedIn'], isTrue);
  });
}

Map<String, dynamic> _row(
  String id, {
  required String createdBy,
  String clientRef = 'their-ref-0001',
  String owedBy = 'me',
  String owedTo = 'ana',
  int amountMinor = 25000,
  String status = 'pending',
  int version = 1,
}) => {
  'id': id,
  'created_by': createdBy,
  'client_ref': clientRef,
  'owed_by': owedBy,
  'owed_to': owedTo,
  'amount_minor': amountMinor,
  'currency': 'INR',
  'entry_date': '2026-11-05',
  'due_date': null,
  'note': 'Dinner',
  'is_opening': false,
  'status': status,
  'version': version,
  'updated_at': '2026-11-05T10:00:00Z',
};

class _FakeApi implements SharedApi {
  final rows = <Map<String, dynamic>>[];
  final applied = <String>[];
  SharedApiException? failNext;

  @override
  Future<void> apply(String token, SharedOp op) async {
    final fail = failNext;
    if (fail != null) {
      failNext = null;
      throw fail;
    }
    switch (op) {
      case AddOp(:final clientRef, :final friendId, :final fields):
        applied.add('add $clientRef');
        rows.add(
          _row(
            'id-$clientRef',
            createdBy: 'me',
            clientRef: clientRef,
            owedBy: fields.theyOwe ? friendId : 'me',
            owedTo: fields.theyOwe ? 'me' : friendId,
            amountMinor: fields.amountMinor,
          ),
        );
      case EditOp(:final clientRef, :final fields):
        applied.add('edit $clientRef');
        final i = rows.indexWhere((r) => r['client_ref'] == clientRef);
        rows[i] = {
          ...rows[i],
          'amount_minor': fields.amountMinor,
          'version': (rows[i]['version'] as int) + 1,
        };
      case DeleteOp(:final clientRef):
        applied.add('delete $clientRef');
        rows.removeWhere((r) => r['client_ref'] == clientRef);
      case RespondOp(:final entryId, :final accept):
        applied.add('respond $entryId $accept');
    }
  }

  @override
  Future<List<SharedEntry>> fetchEntries(String token) async => [
    for (final r in rows) SharedEntry.fromJson(r),
  ];

  @override
  Future<({String? username, List<Profile> friends})> fetchFriends(
    String token,
    String myId,
  ) async => (
    username: 'yash',
    friends: const [Profile(id: 'ana', username: 'ana')],
  );
}
