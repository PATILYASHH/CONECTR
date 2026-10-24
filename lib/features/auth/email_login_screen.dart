import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';

/// Two steps on one screen: email → code. Signing in swaps the gate
/// underneath this route, so on success it just pops.
class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  /// Null while still on the email step.
  String? _sentTo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    await _run(() async {
      await ref.read(authServiceProvider).sendEmailCode(email);
      _codeController.clear();
      setState(() => _sentTo = email);
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    // Supabase's default is 6 digits; the project can raise it to 10.
    if (code.length < 6) {
      setState(() => _error = 'Enter the code from the email.');
      return;
    }
    await _run(() async {
      await ref.read(authServiceProvider).verifyEmailCode(_sentTo!, code);
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;

    return Scaffold(
      appBar: AppBar(title: const Text('Continue with email')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (sentTo == null) ...[
            const Text(
              "We'll email you a code. New here? This creates your account.",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Email'),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _sendCode,
              child: Text(_busy ? 'Sending…' : 'Send code'),
            ),
          ] else ...[
            Text('Enter the code we sent to $sentTo.'),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Code',
                counterText: '',
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _verify,
              child: Text(_busy ? 'Checking…' : 'Sign in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Send a new code'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _sentTo = null;
                      _error = null;
                    }),
              child: const Text('Use a different email'),
            ),
          ],
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
    );
  }
}
