import 'sync_rules.dart';

class AutoSyncSettings {
  const AutoSyncSettings({required this.autoBackup, required this.autoPull});

  /// On by default: someone who installs a backup app expects it to back up.
  static const defaults = AutoSyncSettings(
    autoBackup: AutoBackup.afterXpencBackup,
    autoPull: true,
  );

  final AutoBackup autoBackup;
  final bool autoPull;

  bool get anyOn => autoBackup != AutoBackup.off || autoPull;

  AutoSyncSettings copyWith({AutoBackup? autoBackup, bool? autoPull}) {
    return AutoSyncSettings(
      autoBackup: autoBackup ?? this.autoBackup,
      autoPull: autoPull ?? this.autoPull,
    );
  }
}
