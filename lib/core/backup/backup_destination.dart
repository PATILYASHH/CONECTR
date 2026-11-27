/// Where an account's backups go. One per account — two phones of the same
/// account never back up to different places (see `account_settings`).
enum BackupDestination {
  github('github', 'GitHub'),
  googleDrive('google_drive', 'Google Drive'),
  exoCloud('exocloud', 'ExoCloud');

  const BackupDestination(this.key, this.label);

  /// Stored in `account_settings.backup_destination` and SecureStore.
  final String key;

  /// What the user reads: "Backed up to Google Drive".
  final String label;

  static BackupDestination? fromKey(String? key) {
    for (final d in values) {
      if (d.key == key) return d;
    }
    return null;
  }
}
