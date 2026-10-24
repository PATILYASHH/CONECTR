import 'package:conectr/core/storage/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('overlapping state updates all land', () async {
    // Two stores, as when a provider and a sync service each hold one.
    final a = SecureStore();
    final b = SecureStore();
    await Future.wait([
      a.updateSyncState((s) => s.lastPulledCommitSha = 'pulled'),
      b.updateSyncState((s) => s.baseCommitSha = 'base'),
      a.updateSyncState((s) => s.problem = 'problem'),
    ]);

    final state = await a.getSyncState();
    expect(state.lastPulledCommitSha, 'pulled');
    expect(state.baseCommitSha, 'base');
    expect(state.problem, 'problem');
  });

  test('a failed update doesn\'t block the next', () async {
    final store = SecureStore();
    await expectLater(
      store.updateSyncState((s) => throw StateError('boom')),
      throwsStateError,
    );
    await store.updateSyncState((s) => s.baseCommitSha = 'after');
    expect((await store.getSyncState()).baseCommitSha, 'after');
  });

  test('sign-out forgets everything but which phone this is', () async {
    final store = SecureStore();
    await store.setGithubToken('token');
    await store.setDeviceId('phone-id');
    await store.setDeviceName('Galaxy S23');
    await store.updateSyncState((s) => s.baseCommitSha = 'base');

    await store.clearAll();

    expect(await store.getGithubToken(), isNull);
    expect((await store.getSyncState()).baseCommitSha, isNull);
    expect(await store.getDeviceId(), 'phone-id');
    expect(await store.getDeviceName(), 'Galaxy S23');
  });
}
