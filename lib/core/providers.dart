import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backup/backup_folder_service.dart';
import 'github/github_api.dart';
import 'profile/profile_repository.dart';
import 'storage/secure_store.dart';
import 'supabase/auth_service.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(secureStoreProvider));
});

final githubApiProvider = Provider<GithubApi>((ref) => GithubApi());

final backupFolderServiceProvider =
    Provider<BackupFolderService>((ref) => BackupFolderService());

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository());

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
  return ref.watch(
    authStateProvider.select((s) => s.value?.session?.user.id),
  );
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
