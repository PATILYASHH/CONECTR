import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/backup/auto_sync_settings.dart';
import '../../core/backup/sync_rules.dart';
import '../../core/config/app_config.dart';
import '../../core/notifications/app_notifications.dart';
import '../../core/providers.dart';
import '../../core/supabase/auth_service.dart';
import '../../core/widgets/open_xpenc_button.dart';
import '../../core/widgets/section.dart';
import '../../core/widgets/user_avatar.dart';
import 'auto_sync_labels.dart';

final _versionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(myProfileProvider).value?.username;
    final email = ref.watch(authServiceProvider).currentEmail;
    final githubConnected = ref.watch(githubTokenProvider).value != null;
    final login = ref.watch(githubLoginProvider).value;
    final folderUri = ref.watch(backupFolderUriProvider).value;
    final settings =
        ref.watch(autoSyncSettingsProvider).value ?? AutoSyncSettings.defaults;
    final deviceName = ref.watch(deviceNameProvider).value;
    final version = ref.watch(_versionProvider).value;
    final xpencInstalled = ref.watch(xpencInstalledProvider).value ?? false;
    final backupReady = githubConnected && folderUri != null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Settings')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                Section(
                  title: 'Account',
                  children: [
                    ListTile(
                      leading: UserAvatar(username: username),
                      title: Text(
                        username == null ? 'Your account' : '@$username',
                      ),
                      subtitle: email == null ? null : Text(email),
                    ),
                  ],
                ),
                Section(
                  title: 'Auto-sync',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('Auto-backup'),
                      subtitle: Text(settings.autoBackup.label),
                      enabled: backupReady,
                      onTap: () => _pickAutoBackup(context, ref, settings),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.downloading),
                      title: const Text('Auto-pull'),
                      subtitle: const Text(
                        'Get newer backups from your other phones',
                      ),
                      value: settings.autoPull,
                      onChanged: backupReady
                          ? (on) => _save(ref, settings.copyWith(autoPull: on))
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.smartphone),
                      title: const Text('This phone'),
                      subtitle: Text(
                        deviceName == null
                            ? '…'
                            : '$deviceName — shown on your other phones',
                      ),
                      onTap: deviceName == null
                          ? null
                          : () => _rename(context, ref, deviceName),
                    ),
                  ],
                ),
                Section(
                  title: 'Backup',
                  children: [
                    if (githubConnected)
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: Text(login == null ? 'GitHub' : '@$login'),
                        subtitle: const Text(
                          '${AppConfig.backupRepoName} · private repo',
                        ),
                        trailing: login == null
                            ? null
                            : const Icon(Icons.open_in_new, size: 20),
                        onTap: login == null
                            ? null
                            : () => launchUrl(
                                Uri.parse(
                                  'https://github.com/$login/'
                                  '${AppConfig.backupRepoName}',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: const Text('Connect GitHub'),
                        subtitle: const Text('Turns on backups'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connectGithub(context, ref),
                      ),
                    if (folderUri != null)
                      ListTile(
                        leading: const Icon(Icons.folder_open),
                        title: const Text('Backup folder'),
                        subtitle: Text(_folderLabel(folderUri)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _changeFolder(ref),
                      ),
                  ],
                ),
                Section(
                  title: 'XPENC',
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('Open XPENC'),
                      subtitle: Text(
                        xpencInstalled
                            ? 'Make a backup, or import a pulled one'
                            : 'Not installed on this phone',
                      ),
                      trailing: xpencInstalled
                          ? const Icon(Icons.open_in_new, size: 20)
                          : null,
                      enabled: xpencInstalled,
                      onTap: () => openXpenc(context),
                    ),
                  ],
                ),
                Section(
                  title: 'About',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Version'),
                      subtitle: Text(version ?? '…'),
                    ),
                  ],
                ),
                Section(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Sign out',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onTap: () => _signOut(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `content://…/tree/primary%3ADownload%2FBACKUP%20XPENC` → `Download/BACKUP XPENC`.
String _folderLabel(String treeUri) {
  final decoded = Uri.decodeComponent(treeUri.split('/tree/').last);
  return decoded.contains(':') ? decoded.split(':').last : decoded;
}

Future<void> _save(WidgetRef ref, AutoSyncSettings settings) async {
  await ref.read(autoSyncSettingsProvider.notifier).save(settings);
  if (settings.anyOn) await AppNotifications.requestPermission();
}

Future<void> _pickAutoBackup(
  BuildContext context,
  WidgetRef ref,
  AutoSyncSettings settings,
) async {
  final picked = await showModalBottomSheet<AutoBackup>(
    context: context,
    builder: (context) => SafeArea(
      child: RadioGroup<AutoBackup>(
        groupValue: settings.autoBackup,
        onChanged: (mode) => Navigator.of(context).pop(mode),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Auto-backup',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final mode in AutoBackup.values)
              RadioListTile<AutoBackup>(
                value: mode,
                title: Text(mode.label),
                subtitle: Text(mode.description),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (picked != null) await _save(ref, settings.copyWith(autoBackup: picked));
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final controller = TextEditingController(text: current);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('This phone\'s name'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(
          helperText: 'Shown as "from …" on your other phones',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null) return;
  await ref.read(deviceIdentityProvider).rename(name);
  ref.invalidate(deviceNameProvider);
}

Future<void> _connectGithub(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authServiceProvider).connectGithub();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AuthService.connectErrorMessage(e))),
    );
  }
}

Future<void> _changeFolder(WidgetRef ref) async {
  final uri = await ref.read(backupFolderServiceProvider).pickBackupFolder();
  if (uri == null) return;
  final store = ref.read(secureStoreProvider);
  await store.setBackupFolderUri(uri);
  // A lost-folder problem is what choosing it again fixes; anything else
  // will simply be recorded again on the next run.
  await store.updateSyncState((s) => s.clearProblem());
  ref.invalidate(backupFolderUriProvider);
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
        'Stops auto-sync on this phone and forgets the GitHub connection and '
        'folder here. Your account, username and backups on GitHub stay.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed == true) await ref.read(authServiceProvider).signOut();
}
