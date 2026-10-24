import 'backup_sync_service.dart';

/// XPENC's half of the "I've imported it" step. After importing the backup
/// Connector pulled, XPENC — which never touches the network — offers "Tell
/// Connector", which opens `conectr://imported?sha=<git blob sha of the
/// imported file>` (see `connector_handoff.dart` in XPENC). Connector then
/// confirms the import itself, but only for the file it pulled.
abstract final class ImportLinks {
  static bool matches(Uri uri) =>
      uri.scheme == 'conectr' && uri.host == 'imported';

  /// The fingerprint the link carries, or null if it's not a git blob sha.
  static String? shaOf(Uri uri) {
    final sha = uri.queryParameters['sha']?.toLowerCase();
    return sha != null && RegExp(r'^[0-9a-f]{40}$').hasMatch(sha) ? sha : null;
  }

  /// What the user is told once Connector has looked at the link.
  static String message(ImportHandoff result) => switch (result) {
    ImportHandoff.confirmed =>
      'Import confirmed. Backups from this phone carry on from here.',
    ImportHandoff.differentFile =>
      "XPENC imported a different file from the one Connector pulled, so "
          "nothing changed. If it's the right data, tap \"I've imported it\".",
    ImportHandoff.nothingPending => 'No pulled backup is waiting for import.',
  };
}
