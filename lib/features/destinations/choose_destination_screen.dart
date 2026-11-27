import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_destination.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';

extension DestinationCopy on BackupDestination {
  IconData get icon => switch (this) {
    BackupDestination.googleDrive => Icons.add_to_drive,
    BackupDestination.exoCloud => Icons.cloud_outlined,
    BackupDestination.github => Icons.code,
  };

  String get pitch => switch (this) {
    BackupDestination.googleDrive =>
      'A folder in your own Google Drive that you can see and open. '
          'Sign in with Google and you\'re done.',
    BackupDestination.exoCloud =>
      'Kept for you by ExoSynk Labs, encrypted on your phone so only you '
          'can read it. Free during beta.',
    BackupDestination.github =>
      'A private repo in your GitHub account, with every backup in its '
          'history. For developers.',
  };

  /// "In Google Drive", "In ExoCloud", "On GitHub".
  String get inLabel =>
      this == BackupDestination.github ? 'On GitHub' : 'In $label';
}

/// Where should XPENC's backups go? Asked once per account, on the way into
/// backup; [changing] when switching from Settings.
class ChooseDestinationScreen extends ConsumerStatefulWidget {
  const ChooseDestinationScreen({super.key, this.changing = false});

  final bool changing;

  @override
  ConsumerState<ChooseDestinationScreen> createState() =>
      _ChooseDestinationScreenState();
}

class _ChooseDestinationScreenState
    extends ConsumerState<ChooseDestinationScreen> {
  BackupDestination? _saving;

  Future<void> _pick(BackupDestination destination) async {
    final current = ref.read(backupDestinationProvider).value;
    if (destination == current) {
      Navigator.of(context).maybePop();
      return;
    }
    if (current != null && !await _confirmSwitch(current, destination)) {
      return;
    }
    setState(() => _saving = destination);
    try {
      await ref.read(backupDestinationProvider.notifier).choose(destination);
      if (mounted && widget.changing) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't save your choice: $e")));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<bool> _confirmSwitch(BackupDestination from, BackupDestination to) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Back up to ${to.label} instead?'),
        content: Text(
          'Backups from all your phones go to ${to.label} from now on. Your '
          '${from.label} backups stay where they are, but Connector stops '
          'reading them. Each phone connects to ${to.label} the next time '
          'Connector opens on it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Switch to ${to.label}'),
          ),
        ],
      ),
    ).then((ok) => ok ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(backupDestinationProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.changing ? 'Backup destination' : 'Back up XPENC'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Where should XPENC\'s backups go? All your phones use the same '
              'place, and you can change it later in Settings.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final d in const [
            BackupDestination.googleDrive,
            BackupDestination.exoCloud,
            BackupDestination.github,
          ]) ...[
            _DestinationCard(
              destination: d,
              recommended: d == BackupDestination.googleDrive,
              current: d == current,
              unavailable:
                  d == BackupDestination.googleDrive &&
                      !AppConfig.googleConfigured
                  ? "Not available in this build yet"
                  : null,
              saving: _saving == d,
              onTap: _saving == null ? () => _pick(d) : null,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.recommended,
    required this.current,
    required this.unavailable,
    required this.saving,
    required this.onTap,
  });

  final BackupDestination destination;
  final bool recommended;
  final bool current;
  final String? unavailable;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = unavailable == null && onTap != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: current
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: scheme.onSurface, width: 2),
            )
          : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled ? scheme.primary : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  destination.icon,
                  color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          destination.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (current)
                          _Tag('Current', filled: true)
                        else if (recommended)
                          _Tag('Easiest'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      unavailable ?? destination.pitch,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (saving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (enabled)
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? scheme.primary : null,
        border: Border.all(color: filled ? scheme.primary : scheme.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: filled ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    );
  }
}
