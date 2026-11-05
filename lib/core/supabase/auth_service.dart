import 'package:supabase_flutter/supabase_flutter.dart';

import '../background/auto_sync.dart';
import '../config/app_config.dart';
import '../shared/shared_sync.dart';
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
  ///
  /// Only a sign-in that just finished (`signedIn`, the OAuth redirect) is
  /// sure to carry the newest token. A session restored from disk at
  /// startup carries whichever token its own sign-in got — possibly older
  /// than one saved since, maybe one GitHub has revoked — so it may fill in
  /// a missing token but never replace one. (Replacing it was one way a
  /// working connection read as "revoked" on the next background run.)
  void listenAndPersistGithubToken({required void Function() onSaved}) {
    _auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      final providerToken = session?.providerToken;
      if (providerToken == null || providerToken.isEmpty) return;
      final fresh = state.event == AuthChangeEvent.signedIn;
      final String? stored;
      try {
        stored = await _secureStore.getGithubToken();
      } on SecureStoreException {
        if (!fresh) return;
        // A fresh token overwrites whatever couldn't be read.
        await _secureStore.setGithubToken(providerToken);
        onSaved();
        return;
      }
      if (stored == providerToken || (!fresh && stored != null)) return;
      await _secureStore.setGithubToken(providerToken);
      final login = _githubLogin(session!.user);
      if (login != null) {
        await _secureStore.setGithubLogin(login);
      }
      // A fresh token is exactly what a "Reconnect GitHub" problem needed.
      await _secureStore.updateSyncState((s) {
        if (s.problemNeedsReconnect) s.clearProblem();
      });
      onSaved();
    });
  }

  /// Read from the GitHub identity rather than the top-level metadata: for
  /// an email account that connected GitHub later, that metadata came from
  /// the email sign-up and has no `user_name`.
  static String? _githubLogin(User user) {
    final github = user.identities
        ?.where((i) => i.provider == 'github')
        .firstOrNull;
    final data = github?.identityData ?? user.userMetadata;
    return data?['user_name'] as String? ??
        data?['preferred_username'] as String?;
  }

  /// In a Custom Tab over the app, not the browser app: GitHub remembers an
  /// earlier "Authorize", so reconnecting is usually a blink — the tab opens,
  /// GitHub redirects straight back, and the tab closes as the redirect
  /// reaches the activity (`singleTask`, see AndroidManifest.xml).
  static const _authLaunchMode = LaunchMode.inAppBrowserView;

  Future<bool> signInWithGithub() {
    return _auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: AppConfig.githubOAuthRedirect,
      // `repo` scope is required to create the XPENC-BACKUP repo and push
      // to it. GitHub shows this scope on the consent screen by name.
      scopes: 'repo',
      authScreenLaunchMode: _authLaunchMode,
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
    final hasGithub =
        _auth.currentUser?.identities?.any((i) => i.provider == 'github') ??
        false;
    if (hasGithub) return signInWithGithub();
    return _auth.linkIdentity(
      OAuthProvider.github,
      redirectTo: AppConfig.githubOAuthRedirect,
      scopes: 'repo',
      authScreenLaunchMode: _authLaunchMode,
    );
  }

  /// [connectGithub]'s errors, in words. Supabase's own are terse and name
  /// dashboard settings the user never sees.
  static String connectErrorMessage(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('manual linking')) {
      return 'Connecting GitHub to an email account is switched off for '
          'this Connector. Sign out and continue with GitHub instead.';
    }
    if (text.contains('already') && text.contains('linked')) {
      return 'That GitHub account already belongs to another Connector '
          'account. Sign out and continue with GitHub to use it.';
    }
    if (text.contains('socket') || text.contains('network')) {
      return "Couldn't reach Connector's server. Check your connection.";
    }
    return "Couldn't open GitHub: $error";
  }

  Future<void> signOut() async {
    // Nothing should keep syncing a signed-out account in the background.
    await AutoSyncScheduler.cancel();
    await SharedSyncScheduler.cancel();
    // Store next: signing out re-reads every per-account provider (see
    // `currentUserIdProvider`), and they should find it already empty.
    await _secureStore.clearAll();
    await _auth.signOut();
    // XPENC hears "signed out", and nothing it queued goes out later under
    // whoever signs in next.
    await SharedSync().run(wait: const Duration(seconds: 20));
  }

  Future<String?> getStoredGithubToken() => _secureStore.getGithubToken();

  Future<String?> getStoredGithubLogin() => _secureStore.getGithubLogin();
}
