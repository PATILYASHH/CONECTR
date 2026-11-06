import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/friends/friendship.dart';
import '../../core/friends/friends_failure.dart';
import '../../core/format/when.dart';
import '../../core/providers.dart';
import '../../core/widgets/section.dart';
import '../../core/widgets/user_avatar.dart';
import 'find_friend_screen.dart';
import 'friend_shared_section.dart';
import 'friends_controller.dart';
import 'run_friends_action.dart';
import 'shared_sync_runner.dart';

/// The Friends tab: requests waiting on you, your friends, and requests
/// you've sent. Live — another phone's accept or request shows up here
/// without a refresh.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsControllerProvider);
    final username = ref.watch(myProfileProvider).value?.username;
    final overview = friends.value;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => runFriendsAction(
          context,
          () => ref.read(friendsControllerProvider.notifier).refresh(),
        ),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Friends'),
              actions: [
                IconButton(
                  tooltip: 'Find a friend',
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  onPressed: () => _openFind(context),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.list(
                children: [
                  _SearchPill(onTap: () => _openFind(context)),
                  if (overview != null)
                    ..._lists(context, overview)
                  else if (friends.hasError)
                    _ErrorCard(
                      message: friendsErrorMessage(friends.error!),
                      onRetry: () => ref.invalidate(friendsControllerProvider),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (username != null) _MyUsername(username: username),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _lists(BuildContext context, FriendsOverview overview) {
    if (overview.isEmpty) {
      return [_EmptyCard(onFind: () => _openFind(context))];
    }
    return [
      if (overview.incoming.isNotEmpty)
        Section(
          title: 'Requests · ${overview.incoming.length}',
          children: [
            for (final link in overview.incoming)
              _IncomingTile(key: ValueKey(link.friendshipId), link: link),
          ],
        ),
      if (overview.friends.isNotEmpty)
        Section(
          title: 'Friends · ${overview.friends.length}',
          children: [
            for (final link in overview.friends)
              _FriendTile(key: ValueKey(link.friendshipId), link: link),
          ],
        ),
      if (overview.outgoing.isNotEmpty)
        Section(
          title: 'Sent',
          children: [
            for (final link in overview.outgoing)
              _OutgoingTile(key: ValueKey(link.friendshipId), link: link),
          ],
        ),
    ];
  }
}

void _openFind(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const FindFriendScreen()));
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.search, color: muted),
              const SizedBox(width: 12),
              Text(
                'Find by username',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onFind});

  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                'No friends yet',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask a friend for their Connector username and add them. '
                'Once they accept, you can track who owes whom together.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onFind,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Find a friend'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingTile extends ConsumerStatefulWidget {
  const _IncomingTile({super.key, required this.link});

  final FriendLink link;

  @override
  ConsumerState<_IncomingTile> createState() => _IncomingTileState();
}

class _IncomingTileState extends ConsumerState<_IncomingTile> {
  bool _busy = false;

  Future<void> _respond({required bool accept}) async {
    setState(() => _busy = true);
    final name = widget.link.other.username;
    await runFriendsAction(
      context,
      () => ref
          .read(friendsControllerProvider.notifier)
          .respond(widget.link, accept: accept),
      done: accept ? 'You and @$name are now friends.' : null,
    );
    // On success this tile is gone from the list; on failure it stays.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    return ListTile(
      leading: UserAvatar(username: link.other.username),
      title: Text('@${link.other.username}'),
      subtitle: Text('Wants to be friends · ${formatWhen(link.since)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            tooltip: 'Decline',
            onPressed: _busy ? null : () => _respond(accept: false),
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Accept',
            onPressed: _busy ? null : () => _respond(accept: true),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
    );
  }
}

class _OutgoingTile extends ConsumerStatefulWidget {
  const _OutgoingTile({super.key, required this.link});

  final FriendLink link;

  @override
  ConsumerState<_OutgoingTile> createState() => _OutgoingTileState();
}

class _OutgoingTileState extends ConsumerState<_OutgoingTile> {
  bool _busy = false;

  Future<void> _cancel() async {
    setState(() => _busy = true);
    await runFriendsAction(
      context,
      () => ref.read(friendsControllerProvider.notifier).remove(widget.link),
      done: 'Request cancelled.',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    return ListTile(
      leading: UserAvatar(username: link.other.username),
      title: Text('@${link.other.username}'),
      subtitle: Text('Requested · ${formatWhen(link.since)}'),
      trailing: TextButton(
        onPressed: _busy ? null : _cancel,
        child: const Text('Cancel'),
      ),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({super.key, required this.link});

  final FriendLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = link.other.displayName;
    final balance = balanceLabel(
      ref.watch(sharedBalancesProvider).value?[link.other.id],
    );
    return ListTile(
      leading: UserAvatar(username: link.other.username),
      title: Text('@${link.other.username}'),
      subtitle: Text(
        balance ?? displayName ?? 'Friends since ${_date(link.since)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showFriend(context, ref, link),
    );
  }
}

String _date(DateTime at) => DateFormat.yMMMd().format(at.toLocal());

Future<void> _showFriend(
  BuildContext context,
  WidgetRef ref,
  FriendLink link,
) async {
  final name = link.other.username;
  // Show what was last read straight away, and catch up underneath.
  ref.read(sharedSyncRunnerProvider)?.kick();
  final remove = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(username: name, radius: 32),
              const SizedBox(height: 12),
              Text(
                '@$name',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (link.other.displayName != null) Text(link.other.displayName!),
              const SizedBox(height: 4),
              Text(
                'Friends since ${_date(link.since)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 20),
              FriendSharedSection(friendId: link.other.id, username: name),
              const SizedBox(height: 12),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Remove friend'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (remove != true || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove @$name?'),
      content: Text(
        "You'll stop being friends on both phones. @$name isn't told, but "
        'will no longer see you in their list.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await runFriendsAction(
    context,
    () => ref.read(friendsControllerProvider.notifier).remove(link),
    done: 'Removed @$name.',
  );
}

class _MyUsername extends StatelessWidget {
  const _MyUsername({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Your username',
      children: [
        ListTile(
          leading: const Icon(Icons.alternate_email),
          title: Text('@$username'),
          subtitle: const Text('Friends add you with this'),
          trailing: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: username));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Username copied.')),
                );
            },
          ),
        ),
      ],
    );
  }
}
