import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// The gear icon each top-level screen puts in its app bar.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(myProfileProvider).value?.username;
    final email = ref.watch(authServiceProvider).currentEmail;
    final githubConnected = ref.watch(githubTokenProvider).value != null;
    final login = ref.watch(githubLoginProvider).value;
    final hasFolder = ref.watch(backupFolderUriProvider).value != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(username == null ? 'Connector account' : '@$username'),
            subtitle: email == null ? null : Text(email),
          ),
          const Divider(),
          if (githubConnected)
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(login == null ? 'GitHub connected' : 'GitHub: @$login'),
              subtitle: const Text('Used for backups'),
            )
          else
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Connect GitHub'),
              subtitle: const Text('Turns on backups to a private repo'),
              onTap: () async {
                try {
                  await ref.read(authServiceProvider).connectGithub();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
            ),
          if (hasFolder)
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
              'Your account, username and GitHub backups are untouched.',
            ),
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
