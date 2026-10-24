import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class FolderSetupScreen extends ConsumerStatefulWidget {
  const FolderSetupScreen({super.key});

  @override
  ConsumerState<FolderSetupScreen> createState() => _FolderSetupScreenState();
}

class _FolderSetupScreenState extends ConsumerState<FolderSetupScreen> {
  bool _picking = false;
  String? _error;

  Future<void> _pickFolder() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final folder = ref.read(backupFolderServiceProvider);
      final uri = await folder.pickBackupFolder();
      if (uri == null) return; // user cancelled
      await ref.read(secureStoreProvider).setBackupFolderUri(uri);
      // ignore: unused_result
      ref.invalidate(backupFolderUriProvider);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to XPENC')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.folder_open, size: 64),
            const SizedBox(height: 16),
            Text(
              'One-time setup',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'In XPENC, open Settings → Backup & Restore and take a '
              'backup once if you haven\'t already — it writes a JSON '
              'file into a "Download/BACKUP XPENC" folder.\n\n'
              'Then pick that same folder here so Connector can read and '
              'write it.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _picking ? null : _pickFolder,
              icon: const Icon(Icons.folder),
              label: Text(_picking ? 'Opening…' : 'Choose the folder'),
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
