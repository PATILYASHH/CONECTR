import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_destination.dart';
import '../../core/providers.dart';
import '../../core/widgets/status_screens.dart';
import '../destinations/choose_destination_screen.dart';
import '../destinations/connect_drive_screen.dart';
import '../destinations/exocloud_key_screen.dart';
import '../setup/folder_setup_screen.dart';
import 'backup_screen.dart';
import 'connect_github_screen.dart';

/// Backup needs three things the rest of Connector doesn't: where backups
/// go, a connection to it on this phone, and XPENC's folder. Asked for
/// here, in that order, only on the way into backup.
class BackupGate extends ConsumerWidget {
  const BackupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(backupDestinationProvider);

    return destination.when(
      loading: () => const LoadingScreen(),
      error: (e, _) => ErrorScreen(
        message: '$e',
        onRetry: () => ref.invalidate(backupDestinationProvider),
      ),
      data: (d) {
        if (d == null) return const ChooseDestinationScreen();
        final connected = ref.watch(backupConnectedProvider);
        return connected.when(
          loading: () => const LoadingScreen(),
          error: (e, _) => ErrorScreen(message: '$e'),
          data: (ok) => ok ? const _FolderGate() : _connect(d),
        );
      },
    );
  }

  static Widget _connect(BackupDestination d) => switch (d) {
    BackupDestination.github => const ConnectGithubScreen(),
    BackupDestination.googleDrive => const ConnectDriveScreen(),
    BackupDestination.exoCloud => const ExoCloudKeyScreen(),
  };
}

class _FolderGate extends ConsumerWidget {
  const _FolderGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folderUri = ref.watch(backupFolderUriProvider);
    return folderUri.when(
      loading: () => const LoadingScreen(),
      error: (e, _) => ErrorScreen(message: '$e'),
      data: (uri) =>
          uri == null ? const FolderSetupScreen() : const BackupScreen(),
    );
  }
}
