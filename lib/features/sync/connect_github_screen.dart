import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/supabase/auth_service.dart';

/// For an account with no GitHub token yet — an email sign-up, or a GitHub
/// one whose token was cleared. The token lands via
/// `AuthService.listenAndPersistGithubToken`, which moves [BackupGate] on to
/// the folder step by itself: there's no "done" button to press.
class ConnectGithubScreen extends ConsumerStatefulWidget {
  const ConnectGithubScreen({super.key});

  @override
  ConsumerState<ConnectGithubScreen> createState() =>
      _ConnectGithubScreenState();
}

class _ConnectGithubScreenState extends ConsumerState<ConnectGithubScreen>
    with WidgetsBindingObserver {
  /// GitHub is open over the app, or its answer is on the way back.
  bool _waiting = false;
  String? _message;
  Timer? _giveUp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _giveUp?.cancel();
    super.dispose();
  }

  /// Back in the app. If GitHub finished, the token is a moment behind (the
  /// redirect is still being exchanged) and this screen is about to go; if
  /// the tab was closed instead, say so rather than spin forever.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_waiting) return;
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(seconds: 6), () {
      if (!mounted || !_waiting) return;
      setState(() {
        _waiting = false;
        _message = "GitHub didn't finish connecting. Try again.";
      });
    });
  }

  Future<void> _connect() async {
    _giveUp?.cancel();
    setState(() {
      _waiting = true;
      _message = null;
    });
    try {
      final opened = await ref.read(authServiceProvider).connectGithub();
      if (!opened && mounted) {
        setState(() {
          _waiting = false;
          _message = "Couldn't open GitHub.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _waiting = false;
        _message = AuthService.connectErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect XPENC')),
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
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Backups go to a private ${AppConfig.backupRepoName} repo in '
              'your own GitHub account. Connect once — it stays connected, '
              'and keeps syncing in the background.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _waiting ? null : _connect,
              icon: _waiting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.code),
              label: Text(_waiting ? 'Waiting for GitHub…' : 'Connect GitHub'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
