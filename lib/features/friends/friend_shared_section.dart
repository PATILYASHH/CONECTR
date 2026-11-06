import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/widgets/open_xpenc_button.dart';
import 'shared_sync_runner.dart';

/// What's shared with one friend, in their sheet: where you stand, what's
/// waiting on whom, and the latest entries. Entries are made and answered
/// in XPENC; this only shows them.
class FriendSharedSection extends ConsumerWidget {
  const FriendSharedSection({
    super.key,
    required this.friendId,
    required this.username,
  });

  final String friendId;
  final String username;

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final all = ref.watch(sharedEntriesProvider);
    final installed = ref.watch(xpencInstalledProvider).value ?? false;
    final entries = all.value?[friendId] ?? const <FriendEntry>[];

    final Widget summary;
    if (!all.hasValue) {
      summary = const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (entries.isEmpty) {
      summary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing shared yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'In XPENC, link a person to @$username, then keep '
            '"Share with @$username" on when you add an entry.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      );
    } else {
      final toAnswer = entries.where((e) => e.toAnswer).length;
      final waiting = entries.where((e) => e.waitingOnThem).length;
      summary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            balanceLabel(netOf(entries)) ?? 'All square',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (toAnswer > 0 || waiting > 0) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (toAnswer > 0) '$toAnswer to answer in XPENC',
                if (waiting > 0) '$waiting waiting for @$username',
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ],
      );
    }

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            summary,
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              for (final e in entries.take(_shown)) _EntryRow(entry: e),
              if (entries.length > _shown)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${entries.length - _shown} more in XPENC',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
            ],
            if (installed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => openXpenc(context),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open XPENC'),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final FriendEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final money = moneyLabel(entry.amountMinor, entry.currency);
    final what = entry.isOpening
        ? 'Balance when linked'
        : (entry.note?.trim().isNotEmpty ?? false)
        ? entry.note!.trim()
        : null;
    final (status, statusColor) = switch (entry) {
      FriendEntry(status: 'accepted') => ('Accepted', muted),
      FriendEntry(status: 'rejected') => ('Rejected', theme.colorScheme.error),
      FriendEntry(toAnswer: true) => ('To answer', theme.colorScheme.primary),
      _ => ('Sent', muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.theyOwe ? 'Owes you $money' : 'You owe $money',
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  [?what, _date(entry.date)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            status,
            style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }
}

/// "5 Nov", or "5 Nov 2025" outside this year.
String _date(String ymd) {
  final at = DateTime.tryParse(ymd);
  if (at == null) return ymd;
  return at.year == DateTime.now().year
      ? DateFormat.MMMd().format(at)
      : DateFormat.yMMMd().format(at);
}
