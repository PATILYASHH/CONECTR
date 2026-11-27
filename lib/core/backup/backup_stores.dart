import 'dart:typed_data';

import '../exocloud/exocloud_api.dart';
import '../exocloud/exocloud_backup_store.dart';
import '../github/github_api.dart';
import '../github/github_backup_store.dart';
import '../google/drive_api.dart';
import '../google/drive_backup_store.dart';
import '../storage/secure_store.dart';
import 'backup_destination.dart';
import 'backup_meta.dart';
import 'backup_store.dart';
import 'sync_errors.dart';

/// The store for [destination], or one that's never set up when none is
/// chosen yet. Used by the app's provider and the background job alike.
BackupStore backupStoreFor(
  BackupDestination? destination,
  SecureStore store, {
  GithubApi? github,
}) => switch (destination) {
  BackupDestination.github => GithubBackupStore(github ?? GithubApi(), store),
  BackupDestination.googleDrive => DriveBackupStore(DriveApi(), store),
  BackupDestination.exoCloud => ExoCloudBackupStore(ExoCloudApi(), store),
  null => const UnchosenBackupStore(),
};

/// What this phone last knew the account's destination to be — for the
/// background job, which can't ask Supabase's settings table. An account
/// from before destinations existed, with a GitHub token, is GitHub.
Future<BackupDestination?> cachedDestination(SecureStore store) async {
  final known = BackupDestination.fromKey(await store.getBackupDestination());
  if (known != null) return known;
  if (await store.getGithubToken() != null) return BackupDestination.github;
  return null;
}

/// No destination chosen: never "set up", so auto-sync stays quiet.
class UnchosenBackupStore implements BackupStore {
  const UnchosenBackupStore();

  static Never _choose() =>
      throw SyncSetupException('Choose where to back up XPENC first.');

  @override
  BackupDestination get destination => BackupDestination.github;

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<T> guard<T>(Future<T> Function() attempt) => attempt();

  @override
  Future<bool?> accessWorks() async => null;

  @override
  Future<void> ensureReady() async => _choose();

  @override
  Future<RemoteBackup?> latest() async => _choose();

  @override
  Future<Uint8List?> download(RemoteBackup backup) async => _choose();

  @override
  Future<String?> contentShaOf(RemoteBackup backup) async => _choose();

  @override
  Future<RemoteBackup> upload(
    List<int> bytes,
    BackupMeta meta, {
    required RemoteBackup? replacing,
  }) async => _choose();
}
