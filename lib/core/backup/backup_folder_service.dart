import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart' show SafDocumentFile;

/// Talks to XPENC's own backup folder — the public `Download/BACKUP XPENC`
/// directory XPENC already writes symmetric JSON backups into (see
/// XPENC's `structure.md` §"Backup & Export"). Connector never touches
/// XPENC's private app storage or database directly; it only reads and
/// writes files XPENC itself already knows how to produce and import.
class BackupFolderService {
  BackupFolderService() : _safUtil = SafUtil(), _safStream = SafStream();

  final SafUtil _safUtil;
  final SafStream _safStream;

  /// Opens the SAF folder picker. The user should navigate to and select
  /// XPENC's `Download/BACKUP XPENC` folder. Returns the persisted tree
  /// URI to store (via `SecureStore`) for future sessions, or null if the
  /// user cancelled.
  Future<String?> pickBackupFolder() async {
    final dir = await _safUtil.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    return dir?.uri;
  }

  Future<bool> hasAccess(String treeUri) {
    return _safUtil.hasPersistedPermission(
      treeUri,
      checkRead: true,
      checkWrite: true,
    );
  }

  /// XPENC names every backup `DDMMYYXPENCEBACKUP.json` (see XPENC's
  /// `BackupService.backupFileName`), plus MediaStore's rare "(1)" suffix
  /// when it couldn't replace a same-day file. Matching that — not just any
  /// `.json` — keeps the file Connector itself writes here on restore from
  /// being mistaken for XPENC's newest backup and pushed straight back up.
  static final _xpencBackupName = RegExp(
    r'^\d{6}XPENCEBACKUP(\s?\(\d+\))?\.json$',
  );

  /// The most recently modified backup XPENC has written to the folder, or
  /// null if none exist yet.
  Future<SafDocumentFile?> findLatestBackupFile(String treeUri) async {
    final entries = await _safUtil.list(treeUri);
    final jsonFiles = entries
        .where((e) => !e.isDir && _xpencBackupName.hasMatch(e.name))
        .toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return jsonFiles.isEmpty ? null : jsonFiles.first;
  }

  Future<Uint8List> readFile(String fileUri) {
    return _safStream.readFileBytes(fileUri);
  }

  /// Writes [bytes] as a new backup file into the folder so XPENC's own
  /// restore flow can pick it up. Overwrites a same-named file rather than
  /// piling up duplicates on every sync.
  Future<void> writeRestoredBackup(
    String treeUri,
    String fileName,
    Uint8List bytes,
  ) {
    return _safStream.writeFileBytes(
      treeUri,
      fileName,
      'application/json',
      bytes,
      overwrite: true,
    );
  }
}
