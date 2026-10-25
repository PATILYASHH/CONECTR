import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../backup/sync_state.dart';

/// XPENC's import, as it reports it: which pulled file, and when.
class XpencImport {
  const XpencImport(this.sha, this.at);

  /// Git blob sha of the file XPENC imported.
  final String sha;

  /// When the import finished. Local backups written before it hold the old
  /// data (see `BackupSyncService.confirmImported`).
  final DateTime at;
}

/// What Connector leaves for XPENC, so XPENC can take a pulled backup in by
/// itself — no Import from file, no "I've imported it":
///
/// * which backup is waiting (and the file itself), and
/// * which file this phone's data is built on (`SyncState.baseFileSha`).
///   XPENC compares that with its own data to tell whether taking the
///   waiting backup in could lose anything.
///
/// XPENC reads it through `XpencProvider` (Kotlin), which answers XPENC
/// alone, and reports its import back the same way.
abstract interface class XpencInbox {
  /// Brings what XPENC sees in step with [state]. [pendingBytes]: the
  /// pulled file, when there's a new one.
  Future<void> publish(SyncState state, {List<int>? pendingBytes});

  /// XPENC's report of an import, if it's left one — taken once.
  Future<XpencImport?> takeImport();
}

/// Files in the app's private storage (`getApplicationSupportDirectory()`,
/// `filesDir` on Android) — readable from the app, the background job and
/// `XpencProvider` alike. The provider reads exactly these names.
class FileXpencInbox implements XpencInbox {
  FileXpencInbox([Future<Directory> Function()? root])
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  static const inboxFile = 'inbox.json';
  static const pendingFile = 'pending_backup.json';
  static const importFile = 'imported.json';

  Future<Directory> _dir() async {
    final dir = Directory('${(await _root()).path}/xpenc');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<void> publish(SyncState state, {List<int>? pendingBytes}) async {
    final dir = await _dir();
    final pending = state.pendingImport;
    final pendingPath = File('${dir.path}/$pendingFile');
    if (pending == null) {
      if (await pendingPath.exists()) await pendingPath.delete();
    } else if (pendingBytes != null) {
      await _writeAtomically(pendingPath, pendingBytes);
    }
    await _writeAtomically(
      File('${dir.path}/$inboxFile'),
      utf8.encode(jsonEncode(inboxJson(state))),
    );
  }

  @override
  Future<XpencImport?> takeImport() async {
    final file = File('${(await _dir()).path}/$importFile');
    if (!await file.exists()) return null;
    try {
      return parseImport(await file.readAsString());
    } finally {
      await file.delete();
    }
  }

  static Future<void> _writeAtomically(File file, List<int> bytes) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  /// The shape XPENC reads (`Money-Management/lib/core/connector/inbox/`).
  static Map<String, dynamic> inboxJson(SyncState state) {
    final pending = state.pendingImport;
    return {
      'version': 1,
      'baseFileSha': state.baseFileSha,
      'pending': pending == null || state.pendingImportSha == null
          ? null
          : {
              'sha': state.pendingImportSha,
              'commitSha': pending.commitSha,
              'deviceName': pending.deviceName,
              'backupModifiedAt': pending.backupModifiedAt
                  .toUtc()
                  .toIso8601String(),
            },
    };
  }

  /// What `XpencProvider.confirmImport` writes: `{"sha": …, "at": ms}`.
  static XpencImport? parseImport(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    final sha = json['sha'];
    final at = json['at'];
    if (sha is! String || at is! int) return null;
    return XpencImport(
      sha,
      DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }
}
