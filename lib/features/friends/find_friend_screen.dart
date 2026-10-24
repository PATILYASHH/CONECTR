import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/friends/friendship.dart';
import '../../core/friends/friends_failure.dart';
import '../../core/profile/profile_repository.dart';
import '../../core/profile/username.dart';
import '../../core/profile/username_input.dart';
import '../../core/widgets/user_avatar.dart';
import 'friends_controller.dart';
import 'run_friends_action.dart';

/// Exact-username lookup. Connector never lists or suggests people — you
/// need the name from the friend themselves.
class FindFriendScreen extends ConsumerStatefulWidget {
  const FindFriendScreen({super.key});

  @override
  ConsumerState<FindFriendScreen> createState() => _FindFriendScreenState();
}

class _FindFriendScreenState extends ConsumerState<FindFriendScreen> {
  final _controller = TextEditingController();
  bool _searching = false;
  String? _formatError;
  String? _error;

  /// The name last searched for, and who it found (null: nobody).
  String? _searched;
  Profile? _found;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    if (_searched == null && _formatError == null && _error == null) return;
    setState(() {
      _searched = null;
      _found = null;
      _formatError = null;
      _error = null;
    });
  }

  Future<void> _search() async {
    final name = Username.normalize(_controller.text);
    final formatError = Username.formatError(name);
    if (formatError != null) {
      setState(() => _formatError = formatError);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await ref
          .read(friendsControllerProvider.notifier)
          .findUser(name);
      if (!mounted) return;
      setState(() {
        _searched = name;
        _found = found;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendsErrorMessage(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;

    return Scaffold(
      appBar: AppBar(title: const Text('Find a friend')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: Username.maxLength,
            inputFormatters: usernameInputFormatters,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixText: '@',
              hintText: 'username',
              helperText: 'Their exact username — ask them for it.',
              errorText: _formatError,
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: _searching ? null : _search,
              ),
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            )
          else if (found != null)
            _ResultCard(profile: found)
          else if (_searched != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.person_search_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'No one is called @$_searched',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check the spelling — it has to match exactly.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(FriendsController) action) async {
    setState(() => _busy = true);
    final controller = ref.read(friendsControllerProvider.notifier);
    final name = widget.profile.username;
    await runFriendsAction(context, () async {
      await action(controller);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    // Asking someone who'd already asked you makes you friends at once.
    final relation = ref
        .read(friendsControllerProvider)
        .value
        ?.relationTo(widget.profile.id);
    final message = switch (relation) {
      Relation.friend => 'You and @$name are now friends.',
      Relation.outgoing => 'Request sent to @$name.',
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final overview = ref.watch(friendsControllerProvider).value;
    final relation = overview?.relationTo(profile.id) ?? Relation.none;
    final link = overview?.linkWith(profile.id);

    final Widget action = switch (relation) {
      Relation.self => const Chip(label: Text("That's you")),
      Relation.friend => const OutlinedButton(
        onPressed: null,
        child: Text('Friends'),
      ),
      Relation.outgoing => const OutlinedButton(
        onPressed: null,
        child: Text('Requested'),
      ),
      Relation.incoming => FilledButton(
        onPressed: _busy
            ? null
            : () => _run((c) => c.respond(link!, accept: true)),
        child: const Text('Accept'),
      ),
      Relation.none => FilledButton(
        onPressed: _busy ? null : () => _run((c) => c.sendRequest(profile)),
        child: const Text('Add friend'),
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          leading: UserAvatar(username: profile.username),
          title: Text('@${profile.username}'),
          subtitle: Text(
            relation == Relation.incoming
                ? 'Already asked to be your friend'
                : profile.displayName ?? 'On Connector',
          ),
          trailing: action,
        ),
      ),
    );
  }
}
