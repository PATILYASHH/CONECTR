/// Mirrors the `username_format` check in
/// `supabase/migrations/20261024000001_profiles.sql`. The database is the
/// real gate — this only lets the UI explain a bad name before a round trip.
class Username {
  static const minLength = 3;
  static const maxLength = 20;

  static final _allowed = RegExp(r'^[a-z0-9_]+$');

  /// What the user typed, in the form it's stored: trimmed, lowercase, no
  /// leading "@" (the UI shows one as a prefix, so people type it too).
  static String normalize(String input) {
    final s = input.trim().toLowerCase();
    return s.startsWith('@') ? s.substring(1) : s;
  }

  /// Why [username] (already [normalize]d) can't be used, or null if its
  /// format is fine. Says nothing about whether it's taken.
  static String? formatError(String username) {
    if (username.length < minLength) return 'At least $minLength characters.';
    if (username.length > maxLength) return 'At most $maxLength characters.';
    if (!_allowed.hasMatch(username)) {
      return 'Only lowercase letters, numbers and _.';
    }
    return null;
  }
}
