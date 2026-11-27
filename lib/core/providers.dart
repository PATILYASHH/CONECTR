import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'background/auto_sync.dart';
import 'backup/auto_sync_settings.dart';
import 'backup/backup_folder_service.dart';
import 'backup/backup_sync_service.dart';
import 'device/device_identity.dart';
import 'friends/friends_repository.dart';
import 'github/github_api.dart';
import 'github/github_backup_store.dart';
import 'platform/xpenc_launcher.dart';
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

final deviceIdentityProvider = Provider<DeviceIdentity>((ref) {
  return DeviceIdentity(ref.watch(secureStoreProvider));
});

final deviceNameProvider = FutureProvider<String>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(deviceIdentityProvider).name();
});

final backupSyncServiceProvider = Provider<BackupSyncService>((ref) {
  return BackupSyncService(
    backups: GithubBackupStore(
      ref.watch(githubApiProvider),
      ref.watch(secureStoreProvider),
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
/// backup is set up at all — no job runs for an account without GitHub and
/// a folder. Watched by the home shell, so it lives as long as a session.
final autoSyncScheduleProvider = FutureProvider<void>((ref) async {
  final settings = await ref.watch(autoSyncSettingsProvider.future);
  final token = await ref.watch(githubTokenProvider.future);
  final folder = await ref.watch(backupFolderUriProvider.future);
  await AutoSyncScheduler.apply(
    settings,
    backupReady: token != null && folder != null,
  );
});
