import 'dart:typed_data';

import 'backup_destination.dart';
import 'backup_meta.dart';

/// Thrown when the cloud's latest backup changed between looking at it and
/// writing over it — another phone uploaded in between. Nothing was
/// overwritten; the next run looks again.
class BackupConflictException implements Exception {
  const BackupConflictException();
}

/// Where backups live: a private GitHub repo, a Google Drive folder, or
/// ExoCloud. `BackupSyncService` holds every sync rule; a store only moves
/// versions in and out, so the rules that keep one phone from overwriting
/// another's backup hold the same for each.
abstract interface class BackupStore {
  BackupDestination get destination;

  /// Signed in / authorised on this phone. Without it auto-sync has
  /// nothing to do, which isn't an error worth reporting.
  Future<bool> isConnected();

  /// Runs one whole sync operation. A store whose access can be refused
  /// spuriously (GitHub's occasional 401) retries or reclassifies here.
  Future<T> guard<T>(Future<T> Function() attempt);

  /// Asks, in one request, whether access still works — to clear a
  /// "Reconnect" problem the background job recorded. Null when the store
  /// can't tell; throws when it can't be reached.
  Future<bool?> accessWorks();

  /// Repo / folder exists. Called before an upload.
  Future<void> ensureReady();

  /// Newest backup, or null when there's none.
  Future<RemoteBackup?> latest();

  /// That exact version's bytes; null if it's gone.
  Future<Uint8List?> download(RemoteBackup backup);

  /// Git blob sha of that version's content, without downloading it; null
  /// if unknown (then an upload simply goes ahead).
  Future<String?> contentShaOf(RemoteBackup backup);

  /// Stores [bytes] as the new latest, replacing [replacing] (null: there
  /// was none). Throws [BackupConflictException] if anything else became
  /// latest meanwhile. Returns the new version with the server's time.
  Future<RemoteBackup> upload(
    List<int> bytes,
    BackupMeta meta, {
    required RemoteBackup? replacing,
  });
}
