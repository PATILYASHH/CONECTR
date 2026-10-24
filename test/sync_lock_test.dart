import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:conectr/core/backup/sync_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const quickPing = Duration(milliseconds: 100);

  tearDown(() => IsolateNameServer.removePortNameMapping(SyncLock.name));

  test('a second sync is turned away while the first runs', () async {
    final first = Completer<void>();
    final running = SyncLock.run(() => first.future, pingTimeout: quickPing);

    await expectLater(
      SyncLock.run(() async => 'second', pingTimeout: quickPing),
      throwsA(isA<SyncBusyException>()),
    );

    first.complete();
    await running;
    expect(
      await SyncLock.run(() async => 'after', pingTimeout: quickPing),
      'after',
    );
  });

  test('a waiting sync runs once the first is done', () async {
    final first = Completer<void>();
    final running = SyncLock.run(() => first.future, pingTimeout: quickPing);
    final waiting = SyncLock.run(
      () async => 'waited',
      wait: const Duration(seconds: 5),
      pingTimeout: quickPing,
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    first.complete();
    await running;
    expect(await waiting, 'waited');
  });

  test('released even when the sync fails', () async {
    await expectLater(
      SyncLock.run(() async => throw StateError('boom')),
      throwsStateError,
    );
    expect(await SyncLock.run(() async => 'next'), 'next');
  });

  test('a holder that died without releasing is taken over', () async {
    // What a background run stopped midway leaves behind: the name still
    // registered, nobody listening.
    final dead = ReceivePort();
    IsolateNameServer.registerPortWithName(dead.sendPort, SyncLock.name);
    dead.close();

    expect(
      await SyncLock.run(() async => 'took over', pingTimeout: quickPing),
      'took over',
    );
  });
}
