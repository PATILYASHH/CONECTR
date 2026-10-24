import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/status_screens.dart';
import '../setup/folder_setup_screen.dart';
import 'connect_github_screen.dart';
import 'sync_home_screen.dart';

/// Backup needs two things the rest of Connector doesn't: a GitHub token
/// and XPENC's folder. Asked for here, in order, only on the way into
/// backup.
class BackupGate extends ConsumerWidget {
  const BackupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(githubTokenProvider);

    return token.when(
      loading: () => const LoadingScreen(),
      error: (e, _) => ErrorScreen(message: '$e'),
      data: (t) {
        if (t == null) return const ConnectGithubScreen();

        final folderUri = ref.watch(backupFolderUriProvider);
        return folderUri.when(
          loading: () => const LoadingScreen(),
          error: (e, _) => ErrorScreen(message: '$e'),
          data: (uri) =>
              uri == null ? const FolderSetupScreen() : const SyncHomeScreen(),
        );
      },
    );
  }
}
