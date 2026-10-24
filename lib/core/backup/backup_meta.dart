/// What an upload records about itself, carried in the commit message's
/// trailer lines — so other phones can tell how new the backup on GitHub is
/// and which phone it came from without a second file in the repo.
class BackupMeta {
  const BackupMeta({
    required this.deviceId,
    required this.deviceName,
    required this.backupModifiedAt,
    required this.sourceFileName,
  });

  final String deviceId;
  final String deviceName;

  /// When XPENC wrote the uploaded file — not when it was uploaded. This is
  /// what "newer" compares, so a phone that's been offline for a week can't
  /// win just by uploading last.
  final DateTime backupModifiedAt;

  /// XPENC's own name for it, e.g. `241026XPENCEBACKUP.json`.
  final String sourceFileName;

  static const _prefix = 'Connector-';
  static final _trailer = RegExp(
    r'^Connector-([A-Za-z-]+): (.*)$',
    multiLine: true,
  );

  String toCommitMessage() => [
    'Backup from $deviceName — $sourceFileName',
    '',
    '${_prefix}Device: $deviceName',
    '${_prefix}Device-Id: $deviceId',
    '${_prefix}Backup-Modified: ${backupModifiedAt.toUtc().toIso8601String()}',
    '${_prefix}Source-File: $sourceFileName',
  ].join('\n');

  /// Null for a commit that doesn't carry this metadata — one made before
  /// it existed, or by hand on github.com.
  static BackupMeta? parse(String commitMessage) {
    final fields = {
      for (final m in _trailer.allMatches(commitMessage))
        m.group(1)!: m.group(2)!.trim(),
    };
    final deviceId = fields['Device-Id'];
    final deviceName = fields['Device'];
    final modified = DateTime.tryParse(fields['Backup-Modified'] ?? '');
    if (deviceId == null || deviceName == null || modified == null) {
      return null;
    }
    return BackupMeta(
      deviceId: deviceId,
      deviceName: deviceName,
      backupModifiedAt: modified.toUtc(),
      sourceFileName: fields['Source-File'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'backupModifiedAt': backupModifiedAt.toIso8601String(),
    'sourceFileName': sourceFileName,
  };

  factory BackupMeta.fromJson(Map<String, dynamic> json) => BackupMeta(
    deviceId: json['deviceId'] as String,
    deviceName: json['deviceName'] as String,
    backupModifiedAt: DateTime.parse(json['backupModifiedAt'] as String),
    sourceFileName: json['sourceFileName'] as String,
  );

  /// One line, bounded — a name with a newline in it would otherwise be
  /// able to forge a trailer line of its own.
  static String cleanDeviceName(String name) {
    final oneLine = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.isEmpty) return 'Android phone';
    return oneLine.length > 40 ? oneLine.substring(0, 40) : oneLine;
  }
}

/// The newest commit touching the backup file on GitHub.
class RemoteBackup {
  const RemoteBackup({
    required this.commitSha,
    required this.committedAt,
    this.meta,
  });

  final String commitSha;
  final DateTime committedAt;

  /// Null for an old-style commit; see [BackupMeta.parse].
  final BackupMeta? meta;

  DateTime get backupModifiedAt => meta?.backupModifiedAt ?? committedAt;
  String? get deviceId => meta?.deviceId;
  String? get deviceName => meta?.deviceName;

  Map<String, dynamic> toJson() => {
    'commitSha': commitSha,
    'committedAt': committedAt.toIso8601String(),
    'meta': meta?.toJson(),
  };

  factory RemoteBackup.fromJson(Map<String, dynamic> json) => RemoteBackup(
    commitSha: json['commitSha'] as String,
    committedAt: DateTime.parse(json['committedAt'] as String),
    meta: json['meta'] == null
        ? null
        : BackupMeta.fromJson(json['meta'] as Map<String, dynamic>),
  );
}
