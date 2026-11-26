import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/apps/app_catalog.dart';
import '../../core/backup/auto_sync_settings.dart';
import '../../core/providers.dart';
import '../../core/widgets/section.dart';
import '../connections/connections_screen.dart';
import '../connections/xpenc_status.dart';
import '../friends/friends_controller.dart';
import '../home/home_tab.dart';
import '../settings/auto_sync_labels.dart';
import '../sync/backup_controller.dart';

/// The Dashboard tab: an overview of the account and how each connected
/// app is doing.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final username = ref.watch(myProfileProvider).value?.username;
    final deviceName = ref.watch(deviceNameProvider).value;
    final xpenc = ref.watch(xpencStatusProvider);
    final friends = ref.watch(friendsControllerProvider).value;
    final settings =
        ref.watch(autoSyncSettingsProvider).value ?? AutoSyncSettings.defaults;
    final connected = xpenc.connected ? 1 : 0;
    final requests = friends?.incoming.length ?? 0;

    void goTo(HomeTab tab) => ref.read(homeTabProvider.notifier).select(tab);

    return Scaffold(
      body: RefreshIndicator(
        // Quiet on failure: each card already shows its own trouble.
        onRefresh: () async {
          try {
            await ref.read(friendsControllerProvider.notifier).refresh();
          } catch (_) {}
          if (xpenc.connected && ref.exists(backupControllerProvider)) {
            try {
              await ref.read(backupControllerProvider.notifier).syncNow();
            } catch (_) {}
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Dashboard'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Image.asset(
                    'assets/logo.png',
                    height: 22,
                    color: theme.colorScheme.onSurface,
                    semanticLabel: 'Connector',
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.list(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      [
                        username == null ? 'Welcome back' : 'Hi, @$username',
                        if (deviceName != null) 'on $deviceName',
                      ].join(' '),
                      style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                    ),
                  ),
                  const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _StatTile(
                            value: '$connected/${AppCatalog.available.length}',
                            label: 'Apps connected',
                            onTap: () => goTo(HomeTab.connections),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatTile(
                            value: friends == null
                                ? '–'
                                : '${friends.friends.length}',
                            label: 'Friends',
                            onTap: () => goTo(HomeTab.friends),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatTile(
                            value: friends == null ? '–' : '$requests',
                            label: 'Requests',
                            onTap: () => goTo(HomeTab.friends),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (requests > 0) ...[
                    const SizedBox(height: 12),
                    _RequestsCard(
                      count: requests,
                      onTap: () => goTo(HomeTab.friends),
                    ),
                  ],
                  Section(
                    title: 'Apps',
                    children: [
                      _XpencStatusTile(status: xpenc),
                      for (final app in AppCatalog.comingSoon)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          leading: AppBadge(app: app, dimmed: true),
                          title: Text(app.name),
                          subtitle: const Text('Coming soon'),
                          onTap: () => goTo(HomeTab.connections),
                        ),
                    ],
                  ),
                  Section(
                    title: 'Sync',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('Auto-backup'),
                        subtitle: Text(settings.autoBackup.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => goTo(HomeTab.settings),
                      ),
                      ListTile(
                        leading: const Icon(Icons.downloading),
                        title: const Text('Auto-pull'),
                        subtitle: Text(
                          settings.autoPull ? 'Checks about every hour' : 'Off',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => goTo(HomeTab.settings),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestsCard extends StatelessWidget {
  const _RequestsCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primary,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        iconColor: scheme.onPrimary,
        textColor: scheme.onPrimary,
        leading: const Icon(Icons.person_add_alt_1_outlined),
        title: Text(
          count == 1 ? '1 friend request' : '$count friend requests',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Accept or decline on the Friends tab',
          style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.8)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _XpencStatusTile extends StatelessWidget {
  const _XpencStatusTile({required this.status});

  final XpencStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isProblem = status.tone == StatusTone.problem;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const AppBadge(app: AppCatalog.xpenc),
      title: Row(
        children: [
          Text(AppCatalog.xpenc.name),
          const SizedBox(width: 10),
          StatusDot(tone: status.tone),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isProblem
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      subtitle: status.detail.isEmpty
          ? null
          : Text(status.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openXpencConnection(Navigator.of(context)),
    );
  }
}
