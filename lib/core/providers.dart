import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'background/auto_sync.dart';
import 'backup/auto_sync_settings.dart';
import 'backup/backup_destination.dart';
import 'backup/backup_folder_service.dart';
import 'backup/backup_stores.dart';
import 'backup/backup_sync_service.dart';
import 'device/device_identity.dart';
import 'friends/friends_repository.dart';
import 'github/github_api.dart';
import 'platform/xpenc_launcher.dart';
import 'google/google_auth.dart';
import 'profile/account_settings_repository.dart';
import 'profile/profile_repository.dart';
import 'storage/secure_store.dart';
import 'xpenc/xpenc_inbox.dart';
import 'supabase/auth_service.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(secureStoreProvider));
});

final githubApiProvider = Provider<GithubApi>((ref) => GithubApi());

final backupFolderServiceProvider = Provider<BackupFolderService>(
  (ref) => BackupFolderService(),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(),
);

final friendsRepositoryProvider = Provider<FriendsRepository>(
  (ref) => FriendsRepository(),
);

/// Re-checked when the app comes back to the foreground (see `HomeShell`),
/// in case XPENC was installed meanwhile.
final xpencInstalledProvider = FutureProvider<bool>((ref) {
  return XpencLauncher.isInstalled().catchError((Object _) => false);
});

/// Supabase's own sign-in state — drives routing between the login screen
/// and the rest of the app.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).onAuthStateChange;
});

/// The signed-in user's id, or null. Everything cached per account watches
/// this rather than [authStateProvider] itself — which also fires on every
/// hourly token refresh — so it's re-read exactly when the account changes,
/// sign-out and sign-in included.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider.select((s) => s.value?.session?.user.id));
});

/// The signed-in user's profile, or null if they haven't picked a username
/// yet.
final myProfileProvider = FutureProvider<Profile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchMine(userId);
});

/// The persisted GitHub token, independent of Supabase's session (see
/// [AuthService] for why these two aren't the same thing). Null for an
/// email account that hasn't connected GitHub yet.
final githubTokenProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(authServiceProvider).getStoredGithubToken();
});

final githubLoginProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(authServiceProvider).getStoredGithubLogin();
});

final backupFolderUriProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(secureStoreProvider).getBackupFolderUri();
});

final accountSettingsRepositoryProvider = Provider<AccountSettingsRepository>(
  (ref) => AccountSettingsRepository(),
);

/// Where this account's backups go — null until chosen. Mirrored to
/// SecureStore for the background job. When another phone switched the
/// account to a different destination, this phone follows on its next
/// open: it forgets the old connection and starts over on the new one.
class BackupDestinationNotifier extends AsyncNotifier<BackupDestination?> {
  @override
  Future<BackupDestination?> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;
    final store = ref.read(secureStoreProvider);
    final cached = await cachedDestination(store);

    final AccountSettings settings;
    try {
      settings = await ref
          .read(accountSettingsRepositoryProvider)
          .fetch(userId);
    } catch (_) {
      // Offline: carry on with what this phone last knew.
      return cached;
    }

    final chosen = settings.destination;
    if (chosen == null) {
      // An account from before destinations existed: it's been GitHub.
      if (cached == BackupDestination.github) {
        await ref
            .read(accountSettingsRepositoryProvider)
            .setDestination(userId, BackupDestination.github)
            .catchError((Object _) {});
        await store.setBackupDestination(BackupDestination.github.key);
      }
      return cached;
    }
    if (cached != null && cached != chosen) {
      await store.forgetDestination();
      _invalidateConnections();
    }
    await store.setBackupDestination(chosen.key);
    return chosen;
  }

  /// First choice, or a switch (after the user confirmed it). A switch
  /// forgets this phone's connection to the old destination and the sync
  /// state built on it; the old destination's backups stay where they are.
  Future<void> choose(BackupDestination destination) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final store = ref.read(secureStoreProvider);
    final previous = state.value;
    await ref
        .read(accountSettingsRepositoryProvider)
        .setDestination(userId, destination);
    if (previous != null && previous != destination) {
      await store.forgetDestination();
      if (previous == BackupDestination.googleDrive) {
        await GoogleAuth.signOut().catchError((Object _) {});
      }
      _invalidateConnections();
    }
    await store.setBackupDestination(destination.key);
    state = AsyncData(destination);
  }

  void _invalidateConnections() {
    ref
      ..invalidate(githubTokenProvider)
      ..invalidate(githubLoginProvider)
      ..invalidate(driveEmailProvider)
      ..invalidate(exoCloudKeyProvider)
      ..invalidate(accountSettingsProvider);
  }
}

final backupDestinationProvider =
    AsyncNotifierProvider<BackupDestinationNotifier, BackupDestination?>(
      BackupDestinationNotifier.new,
    );

final accountSettingsProvider = FutureProvider<AccountSettings>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const AccountSettings();
  return ref.watch(accountSettingsRepositoryProvider).fetch(userId);
});

/// The Google account Drive is connected with on this phone, or null.
final driveEmailProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(secureStoreProvider).getDriveEmail();
});

/// Whether this phone holds the account's ExoCloud key.
final exoCloudKeyProvider = FutureProvider<bool>((ref) async {
  ref.watch(currentUserIdProvider);
  return await ref.watch(secureStoreProvider).getExoCloudKey() != null;
});

/// Connected to the chosen destination on this phone (folder aside).
final backupConnectedProvider = FutureProvider<bool>((ref) async {
  final destination = await ref.watch(backupDestinationProvider.future);
  return switch (destination) {
    null => false,
    BackupDestination.github =>
      await ref.watch(githubTokenProvider.future) != null,
    BackupDestination.googleDrive =>
      await ref.watch(driveEmailProvider.future) != null,
    BackupDestination.exoCloud => await ref.watch(exoCloudKeyProvider.future),
  };
});

final deviceIdentityProvider = Provider<DeviceIdentity>((ref) {
  return DeviceIdentity(ref.watch(secureStoreProvider));
});

final deviceNameProvider = FutureProvider<String>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(deviceIdentityProvider).name();
});

final backupSyncServiceProvider = Provider<BackupSyncService>((ref) {
  return BackupSyncService(
    backups: backupStoreFor(
      ref.watch(backupDestinationProvider).value,
      ref.watch(secureStoreProvider),
      github: ref.watch(githubApiProvider),
    ),
    folder: ref.watch(backupFolderServiceProvider),
    store: ref.watch(secureStoreProvider),
    device: ref.watch(deviceIdentityProvider),
    inbox: FileXpencInbox(),
  );
});

class AutoSyncSettingsNotifier extends AsyncNotifier<AutoSyncSettings> {
  @override
  Future<AutoSyncSettings> build() {
    ref.watch(currentUserIdProvider);
    return ref.read(secureStoreProvider).getAutoSyncSettings();
  }

  Future<void> save(AutoSyncSettings settings) async {
    await ref.read(secureStoreProvider).setAutoSyncSettings(settings);
    state = AsyncData(settings);
  }
}

final autoSyncSettingsProvider =
    AsyncNotifierProvider<AutoSyncSettingsNotifier, AutoSyncSettings>(
      AutoSyncSettingsNotifier.new,
    );

/// Keeps the background job in step with the settings and with whether
/// backup is set up at all — no job runs for an account without a
/// connected destination and a folder. Watched by the home shell, so it lives as long as a session.
final autoSyncScheduleProvider = FutureProvider<void>((ref) async {
  final settings = await ref.watch(autoSyncSettingsProvider.future);
  final connected = await ref.watch(backupConnectedProvider.future);
  final folder = await ref.watch(backupFolderUriProvider.future);
  await AutoSyncScheduler.apply(
    settings,
    backupReady: connected && folder != null,
  );
});
