import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import '../config/app_config.dart';

/// Google isn't set up in this build (no `GOOGLE_WEB_CLIENT_ID`).
class GoogleNotConfiguredException implements Exception {
  const GoogleNotConfiguredException();

  @override
  String toString() => "Google sign-in isn't set up in this build.";
}

/// Everything Google, through Play Services (google_sign_in 7). No client
/// secret in the app and no server: sign-in hands an ID token to Supabase,
/// and Drive tokens are fetched from Play Services whenever needed — in the
/// background job too, silently, for the account Drive was connected with.
class GoogleAuth {
  /// Non-sensitive: Connector sees only the files it created itself.
  static const driveScope = 'https://www.googleapis.com/auth/drive.file';

  /// Once per isolate — the app's and the background job's each.
  static Future<void>? _init;

  static Future<void> _ready() {
    if (!AppConfig.googleConfigured) {
      throw const GoogleNotConfiguredException();
    }
    return _init ??= GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleWebClientId,
    );
  }

  /// "Continue with Google": the account picker, then an ID token for
  /// `supabase.auth.signInWithIdToken`.
  static Future<String> signIn() async {
    await _ready();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google returned no ID token.');
    }
    return idToken;
  }

  /// "Connect Google Drive": pick the account, then grant `drive.file`.
  /// Returns that account's email — the hint every later token request
  /// needs on a phone with several Google accounts.
  static Future<String> connectDrive() async {
    await _ready();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: const [driveScope],
    );
    await account.authorizationClient.authorizeScopes(const [driveScope]);
    return account.email;
  }

  /// A Drive access token for [email] without any UI, or null when the
  /// user has to act (access revoked, consent needed): the caller turns
  /// that into "Reconnect Google Drive". Goes through the platform
  /// interface because the app-facing API only hints with a signed-in
  /// account object, which the background job doesn't have.
  static Future<String?> driveToken(String email) async {
    await _ready();
    final tokens = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(
              scopes: const [driveScope],
              userId: null,
              email: email,
              promptIfUnauthorized: false,
            ),
          ),
        );
    return tokens?.accessToken;
  }

  /// Drops a token Drive refused, so the next [driveToken] is fresh.
  static Future<void> forgetToken(String token) async {
    await _ready();
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
  }

  /// So the next sign-in shows the account picker again.
  static Future<void> signOut() async {
    if (!AppConfig.googleConfigured) return;
    await _ready();
    await GoogleSignIn.instance.signOut();
  }
}
