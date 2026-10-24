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

  /// Set for email sign-ins, and for GitHub ones whose GitHub email is
  /// visible to the OAuth app.
  String? get currentEmail => _auth.currentUser?.email;

  /// Call once at startup (after `Supabase.initialize`) to persist the
  /// GitHub token the instant a sign-in redirect delivers one — from a
  /// GitHub sign-in or from [connectGithub] alike. [onSaved] runs after
  /// it's stored, so whatever cached "no token yet" can re-read it.
  void listenAndPersistGithubToken({required void Function() onSaved}) {
    _auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      final providerToken = session?.providerToken;
      if (providerToken == null) return;
      await _secureStore.setGithubToken(providerToken);
      final login = _githubLogin(session!.user);
      if (login != null) {
        await _secureStore.setGithubLogin(login);
      }
      onSaved();
    });
  }

  /// Read from the GitHub identity rather than the top-level metadata: for
  /// an email account that connected GitHub later, that metadata came from
  /// the email sign-up and has no `user_name`.
  static String? _githubLogin(User user) {
    final github =
        user.identities?.where((i) => i.provider == 'github').firstOrNull;
    final data = github?.identityData ?? user.userMetadata;
    return data?['user_name'] as String? ??
        data?['preferred_username'] as String?;
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

  /// Emails a 6-digit sign-in code. Creates the account on first use —
  /// there's no separate sign-up. The code only appears in the email if
  /// the Supabase "Magic Link" template includes `{{ .Token }}`.
  Future<void> sendEmailCode(String email) {
    return _auth.signInWithOtp(email: email, shouldCreateUser: true);
  }

  Future<void> verifyEmailCode(String email, String code) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.email);
  }

  /// Gets a GitHub token for backups without changing which account this
  /// is. A GitHub sign-in already has the identity, so signing in again
  /// just hands back a fresh token. An email account gets GitHub attached
  /// to it instead — Supabase "manual linking", which must be enabled under
  /// Authentication → Sign In / Providers.
  Future<bool> connectGithub() {
    final hasGithub = _auth.currentUser?.identities
            ?.any((i) => i.provider == 'github') ??
        false;
    if (hasGithub) return signInWithGithub();
    return _auth.linkIdentity(
      OAuthProvider.github,
      redirectTo: AppConfig.githubOAuthRedirect,
      scopes: 'repo',
    );
  }

  Future<void> signOut() async {
    // Store first: signing out re-reads every per-account provider (see
    // `currentUserIdProvider`), and they should find it already empty.
    await _secureStore.clearAll();
    await _auth.signOut();
  }

  Future<String?> getStoredGithubToken() => _secureStore.getGithubToken();

  Future<String?> getStoredGithubLogin() => _secureStore.getGithubLogin();
}
