import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exocloud/exocloud_crypto.dart';
import '../../core/providers.dart';
import 'choose_destination_screen.dart';

/// ExoCloud's key on this phone. The account's first phone makes the key
/// and shows it once as a recovery key; every later phone types it in.
/// The key never goes to ExoSynk — only a check value that can't reveal it.
class ExoCloudKeyScreen extends ConsumerWidget {
  const ExoCloudKeyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accountSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ExoCloud'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChooseDestinationScreen(changing: true),
              ),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Retry(
          message: "Couldn't reach ExoCloud. Check your connection.",
          onRetry: () => ref.invalidate(accountSettingsProvider),
        ),
        data: (s) => s.exoCloudKeyCheck == null
            ? const _CreateKey()
            : _EnterKey(check: s.exoCloudKeyCheck!),
      ),
    );
  }
}

/// First phone: make the key, show the recovery key, and only carry on once
/// the user says it's saved.
class _CreateKey extends ConsumerStatefulWidget {
  const _CreateKey();

  @override
  ConsumerState<_CreateKey> createState() => _CreateKeyState();
}

class _CreateKeyState extends ConsumerState<_CreateKey> {
  final _key = ExoCloudCrypto.newKey();
  bool _saved = false;
  bool _busy = false;

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final userId = ref.read(currentUserIdProvider)!;
      // The check first: a phone that dies right after has a key nobody
      // else could ever match, which is safer than the other way round.
      await ref
          .read(accountSettingsRepositoryProvider)
          .setExoCloudKeyCheck(userId, await ExoCloudCrypto.keyCheck(_key));
      await ref.read(secureStoreProvider).setExoCloudKey(_key);
      ref
        ..invalidate(accountSettingsProvider)
        ..invalidate(exoCloudKeyProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't finish setting up ExoCloud: $e")),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final recovery = ExoCloudCrypto.toRecoveryKey(_key);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        const Icon(Icons.key_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          'Save your recovery key',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your backups are locked on this phone before they reach '
          'ExoCloud, so not even ExoSynk can read them. To open them on a '
          'new or reset phone you\'ll need this key. Nobody can recover it '
          'for you — keep it in a password manager or somewhere safe.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 24),
        _RecoveryKeyCard(recoveryKey: recovery),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text("I've saved my recovery key"),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saved && !_busy ? _finish : null,
          child: Text(_busy ? 'Setting up…' : 'Turn on ExoCloud'),
        ),
      ],
    );
  }
}

/// A later phone: type the recovery key; checked against the account's
/// check value before it's used.
class _EnterKey extends ConsumerStatefulWidget {
  const _EnterKey({required this.check});

  final String check;

  @override
  ConsumerState<_EnterKey> createState() => _EnterKeyState();
}

class _EnterKeyState extends ConsumerState<_EnterKey> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = ExoCloudCrypto.fromRecoveryKey(_controller.text);
      if (await ExoCloudCrypto.keyCheck(key) != widget.check) {
        throw const BadRecoveryKeyException(
          "That isn't this account's recovery key.",
        );
      }
      await ref.read(secureStoreProvider).setExoCloudKey(key);
      ref.invalidate(exoCloudKeyProvider);
    } on BadRecoveryKeyException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        const Icon(Icons.lock_open_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          'Enter your recovery key',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your ExoCloud backups are encrypted. Type the recovery key you '
          'saved when you set ExoCloud up on your first phone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1),
          decoration: InputDecoration(
            hintText: 'XXXX-XXXX-XXXX-…',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _unlock,
          child: Text(_busy ? 'Checking…' : 'Unlock ExoCloud'),
        ),
      ],
    );
  }
}

class _RecoveryKeyCard extends StatelessWidget {
  const _RecoveryKeyCard({required this.recoveryKey});

  final String recoveryKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SelectableText(
              recoveryKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 1.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: recoveryKey));
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Recovery key copied.')),
                  );
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows this phone's recovery key again, from Settings.
class RecoveryKeyDialog extends StatelessWidget {
  const RecoveryKeyDialog({super.key, required this.recoveryKey});

  final String recoveryKey;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your recovery key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Anyone with this key and your account can read your ExoCloud '
            'backups. Keep it private.',
          ),
          const SizedBox(height: 16),
          _RecoveryKeyCard(recoveryKey: recoveryKey),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
