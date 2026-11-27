import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/supabase/auth_service.dart';
import 'email_login_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _launching = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      final message = AuthService.googleErrorMessage(e);
      if (mounted) setState(() => _error = message.isEmpty ? null : message);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGithub();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/logo.png',
                height: 64,
                color: Theme.of(context).colorScheme.onSurface,
                semanticLabel: 'Connector logo',
              ),
              const SizedBox(height: 16),
              Text(
                'Connector',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'XPENC stays fully offline. Connector is the optional, '
                'separate app that backs up its data — to your Google Drive, '
                'ExoCloud or GitHub — and syncs it across your devices.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (AppConfig.googleConfigured) ...[
                FilledButton.icon(
                  onPressed: _launching ? null : _signInWithGoogle,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _launching
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EmailLoginScreen(),
                        ),
                      ),
                icon: const Icon(Icons.mail_outline),
                label: const Text('Continue with email'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _launching ? null : _signIn,
                icon: const Icon(Icons.code),
                label: const Text('Continue with GitHub'),
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
      ),
    );
  }
}
