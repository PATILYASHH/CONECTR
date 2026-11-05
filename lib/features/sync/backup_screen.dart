import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/auto_sync_settings.dart';
import '../../core/backup/backup_meta.dart';
import '../../core/backup/backup_sync_service.dart';
import '../../core/backup/sync_failure.dart';
import '../../core/backup/sync_state.dart';
import '../../core/config/app_config.dart';
import '../../core/format/when.dart';
import '../../core/providers.dart';
import '../../core/supabase/auth_service.dart';
import '../../core/widgets/open_xpenc_button.dart';
import '../../core/widgets/sync_icon_button.dart';
import '../home/home_tab.dart';
import '../settings/auto_sync_labels.dart';
import 'backup_controller.dart';

/// The Backup tab once GitHub and the folder are set up (see `BackupGate`).
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(backupControllerProvider);
    final settings =
        ref.watch(autoSyncSettingsProvider).value ?? AutoSyncSettings.defaults;
    final busy = view.busy != null;
    final pending = view.sync.pendingImport;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _syncNow(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              leading: SyncIconButton(
                spinning: busy,
                onPressed: () => _syncNow(context, ref),
              ),
              title: const Text('Backup'),
              actions: const [OpenXpencButton()],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.list(
                children: [
                  _StatusCard(view: view),
                  if (pending != null) ...[
                    const SizedBox(height: 12),
                    _ImportCard(
                      backup: pending,
                      fromElsewhere: view.thisDeviceId != pending.deviceId,
                      canOpenXpenc:
                          ref.watch(xpencInstalledProvider).value ?? false,
                      busy: busy,
                      onOpen: () => ref
                          .read(backupControllerProvider.notifier)
                          .openXpenc(),
                      onImported: () => _confirmImported(context, ref, pending),
                      onKeepThisPhones: () => _upload(context, ref),
                      onDismiss: () => ref
                          .read(backupControllerProvider.notifier)
                          .dismissImport(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _FactTile(
                            label: 'This phone',
                            value: view.localModified == null
                                ? 'No backup yet'
                                : formatWhen(view.localModified!),
                            detail: view.localName ?? 'Make one in XPENC',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _RemoteTile(view: view)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AutoSyncCard(
                    settings: settings,
                    onTap: () => ref
                        .read(homeTabProvider.notifier)
                        .select(HomeTab.settings),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => _upload(context, ref),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Upload now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => _pull(context, ref),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Pull latest'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fromWhom(RemoteBackup remote, String? thisDeviceId) {
  if (remote.deviceId != null && remote.deviceId == thisDeviceId) {
    return 'from this phone';
  }
  return 'from ${remote.deviceName ?? 'another phone'}';
}

Future<void> _syncNow(BuildContext context, WidgetRef ref) {
  return _report(
    context,
    () => ref.read(backupControllerProvider.notifier).syncNow(),
  );
}

Future<void> _upload(BuildContext context, WidgetRef ref) {
  final controller = ref.read(backupControllerProvider.notifier);
  return _report(context, () async {
    var result = await controller.upload();
    if (result is RemoteNotImported) {
      if (!context.mounted) return '';
      final confirmed = await _confirmOverwrite(context, result.remote);
      if (confirmed != true) return '';
      result = await controller.upload(overwriteNewer: true);
    }
    return switch (result) {
      Uploaded() => 'Backed up to GitHub.',
      UploadNotNeeded() => 'Already up to date.',
      NoLocalBackup() =>
        'No XPENC backup in the folder yet. In XPENC: '
            'Settings → Backup & Restore → Backup now.',
      RemoteNotImported() => '',
    };
  });
}

Future<void> _confirmImported(
  BuildContext context,
  WidgetRef ref,
  RemoteBackup backup,
) {
  return _report(context, () async {
    await ref.read(backupControllerProvider.notifier).confirmImported(backup);
    return 'Backups from this phone will carry on from it.';
  });
}

Future<void> _pull(BuildContext context, WidgetRef ref) {
  return _report(context, () async {
    final result = await ref
        .read(backupControllerProvider.notifier)
        .pullLatest();
    return switch (result) {
      Pulled() => 'Saved to the folder as ${AppConfig.backupFileName}.',
      NothingOnGithub() => 'Nothing on GitHub yet.',
      PullNotNeeded() => 'Already up to date.',
    };
  });
}

/// Runs [action] and shows its message (or its failure) as a snack bar.
/// An empty message means "say nothing" — e.g. a cancelled dialog.
Future<void> _report(
  BuildContext context,
  Future<String> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  String message;
  try {
    message = await action();
  } catch (e) {
    message = SyncFailure.from(e).message;
  }
  if (message.isEmpty) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The fresh token lands through `AuthService.listenAndPersistGithubToken`,
/// which clears the problem; the dashboard hears of it by itself.
Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(authServiceProvider).connectGithub();
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AuthService.connectErrorMessage(e))),
      );
  }
}

Future<bool?> _confirmOverwrite(BuildContext context, RemoteBackup remote) {
  final other = remote.deviceName ?? 'another phone';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Replace the backup from $other?'),
      content: Text(
        'GitHub\'s backup is from $other, '
        '${formatWhen(remote.backupModifiedAt)}, and this phone hasn\'t '
        'imported it. Uploading makes this phone\'s backup the latest '
        'instead, so anything added on $other since won\'t be in it. '
        '$other\'s backup stays in the repo\'s history.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Upload anyway'),
        ),
      ],
    ),
  );
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.view});

  final BackupView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sync = view.sync;
    final problem = sync.problem;

    final (IconData icon, String title, String body) = switch (view) {
      BackupView(busy: BackupBusy.upload) => (
        Icons.cloud_upload_outlined,
        'Uploading…',
        'Sending the newest XPENC backup to GitHub.',
      ),
      BackupView(busy: BackupBusy.pull) => (
        Icons.cloud_download_outlined,
        'Downloading…',
        'Fetching the latest backup from GitHub.',
      ),
      BackupView(busy: BackupBusy.checkingAccess) => (
        Icons.sync,
        'Checking GitHub…',
        'Making sure GitHub still accepts this phone.',
      ),
      BackupView(busy: BackupBusy.sync) => (
        Icons.sync,
        'Syncing…',
        'Checking GitHub for anything new.',
      ),
      _ when problem != null => (Icons.error_outline, 'Backup paused', problem),
      _ when view.waitingForImport => (
        Icons.pause_circle_outline,
        'Waiting for import',
        _waitingBody(sync),
      ),
      _ when view.uploadPending => (
        Icons.cloud_upload_outlined,
        'New backup to upload',
        'XPENC made a backup GitHub doesn\'t have yet.',
      ),
      _ when sync.remote == null => (
        Icons.cloud_off_outlined,
        'Not backed up yet',
        'Make a backup in XPENC, then tap Upload now.',
      ),
      _ => (Icons.check_circle_outline, 'Up to date', _lastActivity(view)),
    };
    final isProblem = view.busy == null && problem != null;
    final foreground = isProblem ? scheme.onErrorContainer : scheme.onSurface;

    return Card(
      color: isProblem ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: foreground),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isProblem ? foreground : scheme.onSurfaceVariant,
              ),
            ),
            if (isProblem && sync.problemNeedsReconnect) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _reconnect(context, ref),
                child: const Text('Reconnect GitHub'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _waitingBody(SyncState sync) {
    final other = sync.remote?.deviceName ?? 'another phone';
    final step = sync.pendingImport == null
        ? 'Pull it and import it in XPENC'
        : 'Import it in XPENC (below)';
    return 'GitHub has a backup from $other that this phone hasn\'t '
        'imported, so uploads from here wait. $step — or Upload now to '
        'replace it with this phone\'s.';
  }

  static String _lastActivity(BackupView view) {
    final upload = view.sync.lastUploadAt;
    final check = view.sync.lastCheckAt;
    return [
      if (upload != null) 'Last upload: ${formatWhen(upload)}',
      if (check != null) 'Last check: ${formatWhen(check)}',
    ].join('\n');
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.backup,
    required this.fromElsewhere,
    required this.canOpenXpenc,
    required this.busy,
    required this.onOpen,
    required this.onImported,
    required this.onKeepThisPhones,
    required this.onDismiss,
  });

  final RemoteBackup backup;

  /// Another phone's — not this phone's own, pulled back by hand.
  final bool fromElsewhere;
  final bool canOpenXpenc;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onImported;
  final VoidCallback onKeepThisPhones;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Inverted (black on a light page) — the one thing on this screen that
    // asks the user to do something.
    return Card(
      color: scheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_done, color: scheme.onPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ready to import',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Backup from ${backup.deviceName ?? 'another phone'} '
              '(${formatWhen(backup.backupModifiedAt)}). Open XPENC and it '
              'takes it in by itself — or asks first, if this phone has '
              'changes of its own. With an older XPENC: Settings → Backup & '
              'Restore → Import from file (${AppConfig.backupFileName}), '
              'then tap "I\'ve imported it".',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (canOpenXpenc) ...[
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.onPrimary,
                        foregroundColor: scheme.primary,
                      ),
                      onPressed: onOpen,
                      child: const Text('Open XPENC'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onPrimary,
                      side: BorderSide(color: scheme.onPrimary),
                    ),
                    onPressed: busy ? null : onImported,
                    child: const Text('I\'ve imported it'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.onPrimary),
              // Another phone's data is only set aside by choice, with a
              // confirmation; this phone's own needs no such care.
              onPressed: busy
                  ? null
                  : fromElsewhere
                  ? onKeepThisPhones
                  : onDismiss,
              child: Text(
                fromElsewhere ? 'Keep this phone\'s instead' : 'Dismiss',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({required this.view});

  final BackupView view;

  @override
  Widget build(BuildContext context) {
    final remote = view.sync.remote;
    return _FactTile(
      label: 'On GitHub',
      value: remote == null
          ? 'Nothing yet'
          : formatWhen(remote.backupModifiedAt),
      detail: remote == null
          ? AppConfig.backupRepoName
          : _fromWhom(remote, view.thisDeviceId),
    );
  }
}

class _AutoSyncCard extends StatelessWidget {
  const _AutoSyncCard({required this.settings, required this.onTap});

  final AutoSyncSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Auto-backup'),
            subtitle: Text(settings.autoBackup.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
          const Divider(indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(Icons.downloading),
            title: const Text('Auto-pull'),
            subtitle: Text(
              settings.autoPull ? 'Checks about every hour' : 'Off',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}
