import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_destination.dart';
import '../../core/format/when.dart';
import '../../core/providers.dart';
import '../sync/backup_controller.dart';

enum StatusTone { ok, busy, attention, problem, off }

/// One line about XPENC's connection, for the Dashboard and Connections
/// tabs. The full story is on the XPENC page (`BackupScreen`).
class XpencStatus {
  const XpencStatus({
    required this.tone,
    required this.icon,
    required this.title,
    required this.detail,
    this.lastBackup,
  });

  final StatusTone tone;
  final IconData icon;
  final String title;
  final String detail;

  /// The newest backup on GitHub, when there is one.
  final DateTime? lastBackup;

  /// GitHub and XPENC's folder are both set up.
  bool get connected => tone != StatusTone.off;
}

/// Watching this while backup is set up keeps [backupControllerProvider]
/// alive — which runs the "check on open" sync. The Dashboard watches it
/// from launch, so that check runs whichever tab is showing.
final xpencStatusProvider = Provider<XpencStatus>((ref) {
  final destination = ref.watch(backupDestinationProvider);
  final connected = ref.watch(backupConnectedProvider);
  final folder = ref.watch(backupFolderUriProvider);

  bool loading(AsyncValue<Object?> v) => v.isLoading && !v.hasValue;
  if (loading(destination) ||
      loading(connected) ||
      (connected.value == true && loading(folder))) {
    return const XpencStatus(
      tone: StatusTone.busy,
      icon: Icons.hourglass_empty,
      title: 'Loading…',
      detail: '',
    );
  }
  // A failed read counts as not set up; the XPENC page shows the error.
  final where = destination.value;
  if (where == null) {
    return const XpencStatus(
      tone: StatusTone.off,
      icon: Icons.link_off,
      title: 'Not connected',
      detail: 'Choose where to back up XPENC',
    );
  }
  if (connected.value != true) {
    return XpencStatus(
      tone: StatusTone.off,
      icon: Icons.link_off,
      title: 'Not connected',
      detail: where == BackupDestination.exoCloud
          ? 'Unlock ExoCloud on this phone to back up'
          : 'Connect ${where.label} to back up XPENC',
    );
  }
  if (folder.value == null) {
    return const XpencStatus(
      tone: StatusTone.off,
      icon: Icons.folder_off_outlined,
      title: 'Almost connected',
      detail: "Pick XPENC's backup folder to finish",
    );
  }

  final view = ref.watch(backupControllerProvider);
  final sync = view.sync;
  final remote = sync.remote;
  final last = remote?.backupModifiedAt;
  final lastLine = last == null
      ? null
      : '${where.label} · last backup ${formatWhen(last)}';

  XpencStatus make(StatusTone tone, IconData icon, String title, String d) =>
      XpencStatus(
        tone: tone,
        icon: icon,
        title: title,
        detail: d,
        lastBackup: last,
      );

  if (view.busy != null) {
    return make(StatusTone.busy, Icons.sync, 'Syncing…', lastLine ?? '');
  }
  if (sync.problem != null) {
    return make(
      StatusTone.problem,
      Icons.error_outline,
      'Backup paused',
      sync.problem!,
    );
  }
  if (sync.pendingImport != null) {
    return make(
      StatusTone.attention,
      Icons.download_done,
      'Ready to import',
      'Open XPENC to take in the newest backup',
    );
  }
  if (view.waitingForImport) {
    return make(
      StatusTone.attention,
      Icons.pause_circle_outline,
      'Waiting for import',
      'A newer backup from ${remote?.deviceName ?? 'another phone'} is in '
          '${where.label}',
    );
  }
  if (view.uploadPending) {
    return make(
      StatusTone.attention,
      Icons.cloud_upload_outlined,
      'New backup to upload',
      lastLine ?? "XPENC made a backup ${where.label} doesn't have yet",
    );
  }
  if (remote == null) {
    return make(
      StatusTone.attention,
      Icons.cloud_off_outlined,
      'Not backed up yet',
      'Make a backup in XPENC, then upload it',
    );
  }
  return make(
    StatusTone.ok,
    Icons.check_circle_outline,
    'Up to date',
    lastLine!,
  );
});

/// A small dot coloured by [tone] — monochrome theme, so only problems get
/// a colour.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.tone});

  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, filled) = switch (tone) {
      StatusTone.ok => (scheme.onSurface, true),
      StatusTone.busy => (scheme.onSurfaceVariant, true),
      StatusTone.attention => (scheme.onSurface, false),
      StatusTone.problem => (scheme.error, true),
      StatusTone.off => (scheme.outline, false),
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : null,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}
