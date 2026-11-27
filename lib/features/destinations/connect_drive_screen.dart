import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/google/drive_backup_store.dart';
import '../../core/google/google_auth.dart';
import '../../core/providers.dart';
import 'choose_destination_screen.dart';

/// Connects Google Drive for backups: the account picker, then Google's
/// consent for files Connector creates (`drive.file`) — nothing else in the
/// user's Drive is visible to it.
class ConnectDriveScreen extends ConsumerStatefulWidget {
  const ConnectDriveScreen({super.key});

  @override
  ConsumerState<ConnectDriveScreen> createState() => _ConnectDriveScreenState();
}

class _ConnectDriveScreenState extends ConsumerState<ConnectDriveScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final email = await GoogleAuth.connectDrive();
      final store = ref.read(secureStoreProvider);
      await store.setDriveEmail(email);
      await store.updateSyncState((s) {
        if (s.problemNeedsReconnect) s.clearProblem();
      });
      ref.invalidate(driveEmailProvider);
    } catch (e) {
      final text = '$e'.toLowerCase();
      if (!mounted) return;
      setState(
        () => _message = text.contains('cancel')
            ? null
            : e is GoogleNotConfiguredException
            ? '$e'
            : "Couldn't connect Google Drive: $e",
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Google Drive'),
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.add_to_drive, size: 56),
            const SizedBox(height: 20),
            Text(
              'Back up to Google Drive',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connector keeps XPENC\'s backups in a folder called '
              '"${DriveBackupStore.folderName}" in your Drive. It can only '
              'see files it made there — never the rest of your Drive.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.add_to_drive),
              label: Text(
                _busy ? 'Waiting for Google…' : 'Connect Google Drive',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
