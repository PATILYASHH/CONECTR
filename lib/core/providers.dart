import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backup/backup_folder_service.dart';
import 'github/github_api.dart';
import 'storage/secure_store.dart';
import 'supabase/auth_service.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(secureStoreProvider));
});

final githubApiProvider = Provider<GithubApi>((ref) => GithubApi());

final backupFolderServiceProvider =
    Provider<BackupFolderService>((ref) => BackupFolderService());

/// Supabase's own sign-in state — drives routing between the login screen
/// and the rest of the app.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).onAuthStateChange;
});

/// The persisted GitHub token, independent of Supabase's session (see
/// [AuthService] for why these two aren't the same thing).
final githubTokenProvider = FutureProvider<String?>((ref) {
  return ref.watch(authServiceProvider).getStoredGithubToken();
});

final githubLoginProvider = FutureProvider<String?>((ref) {
  return ref.watch(authServiceProvider).getStoredGithubLogin();
});

final backupFolderUriProvider = FutureProvider<String?>((ref) {
  return ref.watch(secureStoreProvider).getBackupFolderUri();
});
