/// Build-time configuration. Values come from `--dart-define` (or
/// `--dart-define-from-file`) at build/run time — never hardcode a
/// Supabase key or GitHub identifier here, and never commit one to git.
///
/// Run with, e.g.:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// See README.md "Build from source" for how to obtain these values. The
/// Supabase anon key is safe to ship in a client (it's public by design,
/// gated by Row Level Security) — the GitHub OAuth Client Secret is not
/// used here at all, because it lives server-side in the Supabase Auth
/// provider config instead. See docs/ARCHITECTURE.md "Auth".
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Must match an intent-filter in AndroidManifest.xml AND a redirect URL
  /// allow-listed in the Supabase project's Auth > URL Configuration.
  static const githubOAuthRedirect = 'conectr://login-callback';

  static const backupRepoName = 'XPENC-BACKUP';
  static const backupFileName = 'xpenc_backup.json';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
