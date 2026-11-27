/// Thrown for problems the UI should show as plain text, as opposed to a
/// bug — not connected to the backup destination, no folder chosen.
class SyncSetupException implements Exception {
  SyncSetupException(this.message);
  final String message;

  @override
  String toString() => message;
}
