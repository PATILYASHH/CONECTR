import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'shared_entry.dart';

/// One op waiting in the outbox, and the file it's in.
class QueuedOp {
  const QueuedOp(this.file, this.op);

  final File file;

  /// Null when the file couldn't be read as an op.
  final SharedOp? op;
}

/// Connector's half of the shared-entries hand-off with XPENC — files in
/// `filesDir/xpenc/`, beside the backup inbox (`xpenc_inbox.dart`), read and
/// written by `XpencProvider` (Kotlin) for XPENC alone:
///
/// * `outbox/` — what XPENC asked to send, one file per op, named so they
///   sort in the order made. The provider writes them; [SharedSync] sends
///   and deletes them.
/// * `shared.json` — every shared entry this account can see, from its own
///   side, and the ops that failed. What XPENC merges into its persons.
/// * `friends.json` — the friends list, as the background job last read it
///   (the app also publishes it live; the provider hands XPENC the newer).
class SharedFiles {
  SharedFiles([Future<Directory> Function()? root])
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  static const snapshotFile = 'shared.json';
  static const friendsFile = 'friends.json';
  static const outboxDir = 'outbox';
  static const _failedFile = 'shared_failed.json';
  static const _seenFile = 'shared_seen.json';

  /// Failures kept for XPENC to show, newest last.
  static const _keepFailures = 50;

  Future<Directory> _dir([String? sub]) async {
    final base = '${(await _root()).path}/xpenc';
    final dir = Directory(sub == null ? base : '$base/$sub');
    await dir.create(recursive: true);
    return dir;
  }

  /// Oldest first. A file that won't parse comes back with a null op.
  Future<List<QueuedOp>> outbox() async {
    final dir = await _dir(outboxDir);
    final files = [
      for (final entity in dir.listSync())
        if (entity is File && entity.path.endsWith('.json')) entity,
    ]..sort((a, b) => a.path.compareTo(b.path));
    final queued = <QueuedOp>[];
    for (final file in files) {
      SharedOp? op;
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, dynamic>) op = SharedOp.fromJson(json);
      } on FormatException {
        op = null;
      } on FileSystemException {
        continue; // Gone meanwhile.
      }
      queued.add(QueuedOp(file, op));
    }
    return queued;
  }

  Future<void> done(QueuedOp queued) async {
    try {
      await queued.file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  /// Takes [queued] out of the outbox and records why it couldn't be sent,
  /// for XPENC to show against its entry.
  Future<void> fail(QueuedOp queued, String code) async {
    final failures = await readFailures();
    failures.add({
      ...?queued.op?.describe(),
      'opId': queued.op?.opId ?? queued.file.uri.pathSegments.last,
      'error': code,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    final kept = failures.length > _keepFailures
        ? failures.sublist(failures.length - _keepFailures)
        : failures;
    await _writeJson(_failedFile, kept);
    await done(queued);
  }

  Future<List<Map<String, dynamic>>> readFailures() async {
    final raw = await _readJson(_failedFile);
    if (raw is! List) return [];
    return [for (final f in raw) if (f is Map<String, dynamic>) f];
  }

  /// Signing out: nothing queued may go out later under another account.
  Future<void> dropOutbox(String code) async {
    for (final queued in await outbox()) {
      await fail(queued, code);
    }
  }

  Future<void> writeSnapshot({
    required bool signedIn,
    String? myId,
    String? username,
    List<SharedEntry> entries = const [],
    required DateTime now,
  }) async {
    await _writeJson(snapshotFile, {
      'version': 1,
      'signedIn': signedIn,
      'me': myId,
      'username': username,
      'syncedAt': now.millisecondsSinceEpoch,
      'entries': [
        if (myId != null)
          for (final e in entries) e.toWire(myId),
      ],
      'failed': await readFailures(),
    });
  }

  /// The last snapshot's entries, for the app's own screens. Empty when
  /// there's none yet.
  Future<Map<String, dynamic>?> readSnapshot() async {
    final raw = await _readJson(snapshotFile);
    return raw is Map<String, dynamic> ? raw : null;
  }

  Future<void> writeFriends(Map<String, dynamic> payload) =>
      _writeJson(friendsFile, payload);

  /// Ids of incoming entries already announced, at the version announced.
  Future<Map<String, int>> seen() async {
    final raw = await _readJson(_seenFile);
    if (raw is! Map<String, dynamic>) return {};
    return {
      for (final e in raw.entries)
        if (e.value is int) e.key: e.value as int,
    };
  }

  Future<void> saveSeen(Map<String, int> seen) => _writeJson(_seenFile, seen);

  Future<Object?> _readJson(String name) async {
    final file = File('${(await _dir()).path}/$name');
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  /// Write-then-rename, so the provider never reads half a file — and its
  /// file watcher sees one "moved in" per change.
  Future<void> _writeJson(String name, Object json) async {
    final dir = await _dir();
    final file = File('${dir.path}/$name');
    final temp = File('${dir.path}/$name.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }
}
