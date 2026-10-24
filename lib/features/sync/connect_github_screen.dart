import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../settings/settings_screen.dart';

/// For an account with no GitHub token yet — an email sign-up, or a GitHub
/// one whose token was cleared. The token lands via
/// `AuthService.listenAndPersistGithubToken`, which moves [BackupGate] on.
class ConnectGithubScreen extends ConsumerStatefulWidget {
  const ConnectGithubScreen({super.key});

  @override
  ConsumerState<ConnectGithubScreen> createState() =>
      _ConnectGithubScreenState();
}

class _ConnectGithubScreenState extends ConsumerState<ConnectGithubScreen> {
  bool _launching = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).connectGithub();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup'),
        actions: const [SettingsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Connect GitHub',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Backups go to a private ${AppConfig.backupRepoName} repo in '
              'your own GitHub account. Connect GitHub once to turn them on.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _launching ? null : _connect,
              icon: const Icon(Icons.code),
              label: Text(_launching ? 'Opening GitHub…' : 'Connect GitHub'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
