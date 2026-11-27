import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/apps/app_catalog.dart';
import '../../core/config/links.dart';
import '../../core/widgets/section.dart';
import '../sync/backup_gate.dart';
import 'xpenc_status.dart';

/// Opens XPENC's connection page: setup first if needed, then its backup
/// dashboard (see `BackupGate`).
Future<void> openXpencConnection(NavigatorState navigator) {
  return navigator.push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: xpencRouteName),
      builder: (_) => const BackupGate(),
    ),
  );
}

const xpencRouteName = '/connections/xpenc';

/// The Connections tab: the offline-first apps Connector backs up and
/// syncs, and the ones on the way.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Connections')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Your apps stay offline. Connect one here and Connector '
                    'backs it up to Google Drive, ExoCloud or GitHub, and '
                    'keeps it in sync across your phones.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                Section(
                  title: 'Available',
                  children: [
                    for (final app in AppCatalog.available)
                      _AvailableTile(app: app),
                  ],
                ),
                Section(
                  title: 'Coming soon',
                  children: [
                    for (final app in AppCatalog.comingSoon)
                      _ComingSoonTile(app: app),
                  ],
                ),
                Section(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.apps_outlined),
                      title: const Text('More apps from ExoSynk Labs'),
                      subtitle: const Text(
                        'New offline-first apps connect here as they ship',
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 20),
                      onTap: () => _open(Links.exosynkLabs),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lightbulb_outline),
                      title: const Text('Suggest an app'),
                      subtitle: const Text(
                        'Tell us what Connector should support',
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 20),
                      onTap: () => _open(Links.requestFeature),
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

Future<void> _open(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.app, this.dimmed = false});

  final LinkedApp app;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: dimmed ? scheme.surfaceContainerHigh : scheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        app.icon,
        color: dimmed ? scheme.onSurfaceVariant : scheme.onPrimary,
      ),
    );
  }
}

class _AvailableTile extends ConsumerWidget {
  const _AvailableTile({required this.app});

  final LinkedApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // XPENC is the only available app so far; a second one brings its own
    // status provider.
    final status = ref.watch(xpencStatusProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: AppBadge(app: app),
      title: Text(app.name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            StatusDot(tone: status.tone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      trailing: status.connected
          ? const Icon(Icons.chevron_right)
          : FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () => openXpencConnection(Navigator.of(context)),
              child: const Text('Connect'),
            ),
      onTap: () => openXpencConnection(Navigator.of(context)),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({required this.app});

  final LinkedApp app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: AppBadge(app: app, dimmed: true),
      title: Text(app.name),
      subtitle: Text(app.tagline),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('Soon', style: theme.textTheme.labelMedium),
      ),
    );
  }
}
