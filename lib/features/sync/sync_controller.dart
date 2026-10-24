import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_folder_service.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_api.dart';
import '../../core/providers.dart';
import '../../core/storage/secure_store.dart';

class SyncStatus {
  const SyncStatus({
    this.isBusy = false,
    this.message,
    this.isError = false,
    this.lastSyncedAt,
  });

  final bool isBusy;
  final String? message;
  final bool isError;
  final DateTime? lastSyncedAt;

  SyncStatus copyWith({
    bool? isBusy,
    String? message,
    bool? isError,
    DateTime? lastSyncedAt,
  }) {
    return SyncStatus(
      isBusy: isBusy ?? this.isBusy,
      message: message,
      isError: isError ?? false,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

/// Thrown for problems the UI should show as plain text, as opposed to a
/// bug — not signed in, no folder chosen, nothing to back up yet.
class SyncSetupException implements Exception {
  SyncSetupException(this.message);
  final String message;
}

/// Orchestrates one round trip between XPENC's shared backup folder and
/// the user's `XPENC-BACKUP` GitHub repo. Connector never reads XPENC's
/// private database — it only ever moves the JSON file XPENC itself
/// already knows how to export and import.
class SyncController extends Notifier<SyncStatus> {
  // Getters, not `late final` fields set in build(): build() runs again
  // whenever the provider is invalidated (e.g. on sign-out), and a second
  // assignment to a `late final` throws.
  GithubApi get _github => ref.read(githubApiProvider);
  BackupFolderService get _folder => ref.read(backupFolderServiceProvider);
  SecureStore get _store => ref.read(secureStoreProvider);

  @override
  SyncStatus build() {
    _loadLastSyncedAt();
    return const SyncStatus();
  }

  /// "Last synced" is persisted on every sync — show it from launch, not
  /// only after this session's first sync.
  Future<void> _loadLastSyncedAt() async {
    final last = await _store.getLastSyncedAt();
    if (!ref.mounted || last == null || state.lastSyncedAt != null) return;
    state = SyncStatus(
      isBusy: state.isBusy,
      message: state.message,
      isError: state.isError,
      lastSyncedAt: last,
    );
  }

  Future<_SyncContext> _requireContext() async {
    final token = await _store.getGithubToken();
    if (token == null) {
      throw SyncSetupException('Not signed in to GitHub yet.');
    }
    final folderUri = await _store.getBackupFolderUri();
    if (folderUri == null) {
      throw SyncSetupException(
        'No backup folder chosen yet. Point Connector at XPENC\'s '
        '"Download/BACKUP XPENC" folder first.',
      );
    }
    var owner = await _store.getGithubLogin();
    if (owner == null) {
      owner = await _github.getAuthenticatedLogin(token);
      await _store.setGithubLogin(owner);
      ref.invalidate(githubLoginProvider);
    }
    return _SyncContext(token: token, folderUri: folderUri, owner: owner);
  }

  Future<void> _ensureRepoReady(String token, String owner) async {
    final exists = await _github.repoExists(
      token,
      owner,
      AppConfig.backupRepoName,
    );
    if (!exists) {
      await _github.createPrivateRepo(token, AppConfig.backupRepoName);
    }
  }

  Future<void> backupNow() async {
    state = state.copyWith(isBusy: true, message: null);
    try {
      final ctx = await _requireContext();
      final latestLocal = await _folder.findLatestBackupFile(ctx.folderUri);
      if (latestLocal == null) {
        throw SyncSetupException(
          'No XPENC backup found in that folder yet. Open XPENC → '
          'Settings → Backup & Restore → Backup Now first.',
        );
      }
      final bytes = await _folder.readFile(latestLocal.uri);
      await _ensureRepoReady(ctx.token, ctx.owner);
      final existing = await _github.getFile(
        ctx.token,
        ctx.owner,
        AppConfig.backupRepoName,
        AppConfig.backupFileName,
      );
      await _github.putFile(
        ctx.token,
        ctx.owner,
        AppConfig.backupRepoName,
        AppConfig.backupFileName,
        contentBytes: bytes,
        commitMessage: 'Backup from Connector — ${latestLocal.name}',
        existingSha: existing?.sha,
      );
      final now = DateTime.now();
      await _store.setLastSyncedAt(now);
      state = SyncStatus(
        message: 'Backed up "${latestLocal.name}" to GitHub.',
        lastSyncedAt: now,
      );
    } on SyncSetupException catch (e) {
      state = state.copyWith(message: e.message, isError: true, isBusy: false);
    } on GithubApiException catch (e) {
      state = state.copyWith(
        message: 'GitHub error: ${e.message}',
        isError: true,
        isBusy: false,
      );
    } catch (e) {
      state = state.copyWith(
        message: 'Backup failed: $e',
        isError: true,
        isBusy: false,
      );
    }
  }

  Future<void> restoreLatest() async {
    state = state.copyWith(isBusy: true, message: null);
    try {
      final ctx = await _requireContext();
      final remote = await _github.getFile(
        ctx.token,
        ctx.owner,
        AppConfig.backupRepoName,
        AppConfig.backupFileName,
      );
      if (remote == null) {
        throw SyncSetupException(
          'No backup found on GitHub yet — nothing to restore.',
        );
      }
      await _folder.writeRestoredBackup(
        ctx.folderUri,
        AppConfig.backupFileName,
        remote.contentBytes,
      );
      final now = DateTime.now();
      await _store.setLastSyncedAt(now);
      state = SyncStatus(
        // XPENC's own backup list only shows files it named itself
        // (DDMMYYXPENCEBACKUP.json), so this one goes in via Import.
        message: 'Saved as "${AppConfig.backupFileName}" in the backup '
            'folder. To finish, open XPENC → Settings → Backup & Restore → '
            'Import from file and pick it.',
        lastSyncedAt: now,
      );
    } on SyncSetupException catch (e) {
      state = state.copyWith(message: e.message, isError: true, isBusy: false);
    } on GithubApiException catch (e) {
      state = state.copyWith(
        message: 'GitHub error: ${e.message}',
        isError: true,
        isBusy: false,
      );
    } catch (e) {
      state = state.copyWith(
        message: 'Restore failed: $e',
        isError: true,
        isBusy: false,
      );
    }
  }
}

class _SyncContext {
  _SyncContext({
    required this.token,
    required this.folderUri,
    required this.owner,
  });

  final String token;
  final String folderUri;
  final String owner;
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
