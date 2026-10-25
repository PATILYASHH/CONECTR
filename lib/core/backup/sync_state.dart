import 'backup_meta.dart';

/// Everything sync remembers between runs and between the app and the
/// background job, stored as one JSON blob (see `SecureStore`). Mutable on
/// purpose: every writer loads it, changes a field or two, and saves it.
class SyncState {
  SyncState();

  /// When this phone last actually uploaded.
  DateTime? lastUploadAt;

  /// The newest local XPENC backup already dealt with — uploaded, found
  /// identical, or found older than GitHub's. Anything not newer than this
  /// is answered from the folder alone, with no network call.
  DateTime? lastHandledLocalModified;

  DateTime? lastAutoBackupRunAt;
  DateTime? lastPullCheckAt;

  /// Last time GitHub was successfully asked anything.
  DateTime? lastCheckAt;

  DateTime? lastPullAt;
  String? lastPulledCommitSha;

  /// The commit this phone's XPENC data is built on: its own last upload,
  /// or the pulled backup the user confirmed importing. Uploads only ever
  /// replace this one (see `isFromElsewhere`).
  String? baseCommitSha;

  /// The newest backup on GitHub, as last seen.
  RemoteBackup? remote;

  /// A pulled backup sitting in the folder that the user hasn't confirmed
  /// importing yet. Cleared by that confirmation, or by an upload replacing
  /// it on GitHub.
  RemoteBackup? pendingImport;

  /// The git blob sha of the file [pendingImport] was saved as — what
  /// XPENC's "Tell Connector" link must name for the import to count (see
  /// `BackupSyncService.confirmImportedFile`).
  String? pendingImportSha;

  /// The git blob sha of the file [baseCommitSha] holds — the backup this
  /// phone uploaded, or the pulled one XPENC imported. XPENC matches it
  /// against its own data to know whether taking in a newer backup could
  /// lose anything (see `XpencInbox`). Null until the next upload or import.
  String? baseFileSha;

  /// Why auto-sync is stuck, for the dashboard's red card. Null when fine.
  String? problem;
  bool problemNeedsReconnect = false;

  void clearProblem() {
    problem = null;
    problemNeedsReconnect = false;
  }

  void clearPendingImport() {
    pendingImport = null;
    pendingImportSha = null;
  }

  Map<String, dynamic> toJson() => {
    'lastUploadAt': lastUploadAt?.toIso8601String(),
    'lastHandledLocalModified': lastHandledLocalModified?.toIso8601String(),
    'lastAutoBackupRunAt': lastAutoBackupRunAt?.toIso8601String(),
    'lastPullCheckAt': lastPullCheckAt?.toIso8601String(),
    'lastCheckAt': lastCheckAt?.toIso8601String(),
    'lastPullAt': lastPullAt?.toIso8601String(),
    'lastPulledCommitSha': lastPulledCommitSha,
    'baseCommitSha': baseCommitSha,
    'remote': remote?.toJson(),
    'pendingImport': pendingImport?.toJson(),
    'pendingImportSha': pendingImportSha,
    'baseFileSha': baseFileSha,
    'problem': problem,
    'problemNeedsReconnect': problemNeedsReconnect,
  };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => DateTime.tryParse(json[key] as String? ?? '');
    RemoteBackup? backup(String key) => json[key] == null
        ? null
        : RemoteBackup.fromJson(json[key] as Map<String, dynamic>);

    return SyncState()
      ..lastUploadAt = time('lastUploadAt')
      ..lastHandledLocalModified = time('lastHandledLocalModified')
      ..lastAutoBackupRunAt = time('lastAutoBackupRunAt')
      ..lastPullCheckAt = time('lastPullCheckAt')
      ..lastCheckAt = time('lastCheckAt')
      ..lastPullAt = time('lastPullAt')
      ..lastPulledCommitSha = json['lastPulledCommitSha'] as String?
      ..baseCommitSha = json['baseCommitSha'] as String?
      ..remote = backup('remote')
      ..pendingImport = backup('pendingImport')
      ..pendingImportSha = json['pendingImportSha'] as String?
      ..baseFileSha = json['baseFileSha'] as String?
      ..problem = json['problem'] as String?
      ..problemNeedsReconnect = json['problemNeedsReconnect'] as bool? ?? false;
  }
}
