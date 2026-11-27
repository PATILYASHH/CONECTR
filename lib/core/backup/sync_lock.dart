import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Another sync — the app's or the background job's — held the lock for
/// longer than the caller was willing to wait.
class SyncBusyException implements Exception {}

/// One sync at a time, across the app and the background job.
///
/// Those are two Flutter engines in one process, so a file lock can't tell
/// them apart (POSIX locks belong to the process); the [IsolateNameServer]
/// registry is shared by both. Whoever registers the name holds the lock
/// and answers pings for as long as its isolate lives — so a holder that
/// died without releasing (WorkManager stopping a run midway) is noticed and
/// replaced instead of blocking sync until the process exits.
///
/// Not reentrant: an isolate already holding it waits on itself.
class SyncLock {
  SyncLock._(this._port, this._name);

  /// The backup sync's lock — the default.
  @visibleForTesting
  static const name = 'connector-sync-lock';

  /// Friends' shared entries sync on their own, beside backups.
  static const sharedName = 'connector-shared-lock';

  /// Held only while the background job refreshes the Supabase session —
  /// the app waits for it before reading that session (see
  /// `SessionTokens`).
  static const sessionName = 'connector-session-lock';

  final ReceivePort _port;
  final String _name;

  /// Runs [action] holding the lock, waiting up to [wait] for it. Throws
  /// [SyncBusyException], without running [action], if it stayed taken.
  /// [pingTimeout] is how long a holder gets to answer — shortened only by
  /// tests.
  static Future<T> run<T>(
    Future<T> Function() action, {
    Duration wait = Duration.zero,
    Duration pingTimeout = const Duration(seconds: 2),
    String lock = name,
  }) async {
    final deadline = DateTime.now().add(wait);
    SyncLock? held;
    while ((held = await _tryAcquire(lock, pingTimeout)) == null) {
      if (!DateTime.now().isBefore(deadline)) throw SyncBusyException();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    try {
      return await action();
    } finally {
      held!._release();
    }
  }

  static Future<SyncLock?> _tryAcquire(
    String name,
    Duration pingTimeout,
  ) async {
    final port = ReceivePort();
    port.listen((message) {
      if (message is SendPort) message.send(true);
    });
    if (IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      return SyncLock._(port, name);
    }
    final holder = IsolateNameServer.lookupPortByName(name);
    if (holder != null && await _answers(holder, pingTimeout)) {
      port.close();
      return null;
    }
    // Its isolate is gone. Take over — unless someone else just did.
    if (IsolateNameServer.lookupPortByName(name) == holder) {
      IsolateNameServer.removePortNameMapping(name);
    }
    if (IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      return SyncLock._(port, name);
    }
    port.close();
    return null;
  }

  static Future<bool> _answers(SendPort holder, Duration timeout) async {
    final reply = ReceivePort();
    holder.send(reply.sendPort);
    try {
      await reply.first.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }

  void _release() {
    if (IsolateNameServer.lookupPortByName(_name) == _port.sendPort) {
      IsolateNameServer.removePortNameMapping(_name);
    }
    _port.close();
  }
}
