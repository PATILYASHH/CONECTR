import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_repository.dart';
import '../../core/profile/username.dart';
import '../../core/profile/username_input.dart';
import '../../core/providers.dart';

enum _Availability { unknown, checking, available, taken, unreachable }

/// Shown once per account, right after the first sign-in. Saving
/// invalidates [myProfileProvider], which swaps the gate past this screen.
class UsernameScreen extends ConsumerStatefulWidget {
  const UsernameScreen({super.key});

  @override
  ConsumerState<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends ConsumerState<UsernameScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _Availability _availability = _Availability.unknown;
  bool _saving = false;
  String? _error;

  String get _name => Username.normalize(_controller.text);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    final name = _name;
    final valid = Username.formatError(name) == null;
    setState(() {
      _error = null;
      _availability = valid ? _Availability.checking : _Availability.unknown;
    });
    if (!valid) return;
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _checkAvailability(name),
    );
  }

  Future<void> _checkAvailability(String name) async {
    _Availability result;
    try {
      final free = await ref
          .read(profileRepositoryProvider)
          .isUsernameAvailable(name);
      result = free ? _Availability.available : _Availability.taken;
    } catch (_) {
      result = _Availability.unreachable;
    }
    // The user may have kept typing while this was in flight.
    if (!mounted || name != _name) return;
    setState(() => _availability = result);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).claimUsername(_name);
      ref.invalidate(myProfileProvider);
    } on UsernameTakenException {
      if (mounted) {
        setState(() {
          _availability = _Availability.taken;
          _error = 'That username was just taken.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? get _helperText {
    final name = _name;
    return switch (_availability) {
      _Availability.checking => 'Checking…',
      _Availability.available => '@$name is available',
      _Availability.unreachable => "Couldn't check right now.",
      _ => null,
    };
  }

  String? get _errorText {
    final name = _name;
    if (name.isEmpty) return null;
    return Username.formatError(name) ??
        (_availability == _Availability.taken ? '@$name is taken' : null);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _availability == _Availability.available && !_saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a username'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => ref.read(authServiceProvider).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Friends find you by this exact name, so pick one you\'d '
            'share. ${Username.minLength}–${Username.maxLength} characters: '
            'lowercase letters, numbers and _.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: Username.maxLength,
            inputFormatters: usernameInputFormatters,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              helperText: _helperText,
              errorText: _errorText,
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => canSave ? _save() : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canSave ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Continue'),
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
    );
  }
}
