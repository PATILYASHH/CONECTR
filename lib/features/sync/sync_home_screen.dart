import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../settings/settings_screen.dart';
import 'sync_controller.dart';

class SyncHomeScreen extends ConsumerWidget {
  const SyncHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final login = ref.watch(githubLoginProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connector'),
        actions: const [SettingsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.code),
                title: Text(login == null ? 'GitHub' : '@$login'),
                subtitle: Text('${AppConfig.backupRepoName} (private repo)'),
              ),
            ),
            const SizedBox(height: 8),
            if (status.lastSyncedAt != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Last synced: '
                  '${DateFormat.yMMMd().add_jm().format(status.lastSyncedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Spacer(),
            if (status.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  status.message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: status.isError
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: status.isBusy
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).backupNow(),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(status.isBusy ? 'Working…' : 'Backup now'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: status.isBusy
                  ? null
                  : () =>
                      ref.read(syncControllerProvider.notifier).restoreLatest(),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Restore latest'),
            ),
          ],
        ),
      ),
    );
  }
}
