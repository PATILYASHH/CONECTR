import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';

/// Wraps Supabase Auth for the one thing Connector needs from it: a GitHub
/// login that hands back a token good enough to call the GitHub REST API.
///
/// Supabase only returns `session.providerToken` (the GitHub access token)
/// in the redirect that completes the OAuth flow — it is *not* included in
/// a session restored from disk on a later launch, and Supabase's own
/// token refresh does not renew it. So the moment it appears in
/// [onAuthStateChange], it's captured here and persisted in
/// [SecureStore]. Everything after that reads it from there, not from
/// `supabase.auth.currentSession`.
class AuthService {
  AuthService(this._secureStore);

  final SecureStore _secureStore;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  bool get isSignedIn => _auth.currentSession != null;

  /// Call once at startup (after `Supabase.initialize`) to persist the
  /// GitHub token the instant a sign-in redirect delivers one.
  void listenAndPersistGithubToken() {
    _auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      final providerToken = session?.providerToken;
      if (providerToken != null) {
        await _secureStore.setGithubToken(providerToken);
        final login = session!.user.userMetadata?['user_name'] as String? ??
            session.user.userMetadata?['preferred_username'] as String?;
        if (login != null) {
          await _secureStore.setGithubLogin(login);
        }
      }
    });
  }

  Future<bool> signInWithGithub() {
    return _auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: AppConfig.githubOAuthRedirect,
      // `repo` scope is required to create the XPENC-BACKUP repo and push
      // to it. GitHub shows this scope on the consent screen by name.
      scopes: 'repo',
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _secureStore.clearAll();
  }

  Future<String?> getStoredGithubToken() => _secureStore.getGithubToken();

  Future<String?> getStoredGithubLogin() => _secureStore.getGithubLogin();
}
