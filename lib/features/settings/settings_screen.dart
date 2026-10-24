import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../sync/sync_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final login = ref.watch(githubLoginProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(login == null ? 'GitHub account' : '@$login'),
            subtitle: const Text('Connected via Supabase OAuth'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Change backup folder'),
            subtitle: const Text('Pick a different XPENC backup folder'),
            onTap: () async {
              final folder = ref.read(backupFolderServiceProvider);
              final uri = await folder.pickBackupFolder();
              if (uri == null) return;
              await ref.read(secureStoreProvider).setBackupFolderUri(uri);
              // ignore: unused_result
              ref.invalidate(backupFolderUriProvider);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign out', style: TextStyle(color: Colors.red)),
            subtitle: const Text(
              'Clears the stored GitHub token and folder on this device. '
              'Your GitHub repo and its backups are untouched.',
            ),
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              // These cache what signOut just wiped from SecureStore —
              // without this, signing back in would skip folder setup and
              // still show the previous account.
              ref
                ..invalidate(githubTokenProvider)
                ..invalidate(githubLoginProvider)
                ..invalidate(backupFolderUriProvider)
                ..invalidate(syncControllerProvider);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
