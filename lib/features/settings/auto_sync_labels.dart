import '../../core/backup/sync_rules.dart';

extension AutoBackupLabels on AutoBackup {
  String get label => switch (this) {
    AutoBackup.off => 'Off',
    AutoBackup.afterXpencBackup => 'After every XPENC backup',
    AutoBackup.daily => 'Once a day',
    AutoBackup.weekly => 'Once a week',
  };

  String get description => switch (this) {
    AutoBackup.off => 'Only when you tap Upload now',
    AutoBackup.afterXpencBackup =>
      'Within about 15 minutes of XPENC making one',
    AutoBackup.daily => 'The newest XPENC backup, once a day',
    AutoBackup.weekly => 'The newest XPENC backup, once a week',
  };
}
