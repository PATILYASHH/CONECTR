import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/setup/folder_setup_screen.dart';
import 'features/sync/sync_home_screen.dart';

class ConectrApp extends StatelessWidget {
  const ConectrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connector',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _Gate(),
    );
  }
}

/// Three states, checked in order: signed in to GitHub? backup folder
/// chosen? Only then does the sync home screen make sense.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _Splash(),
      error: (e, _) => _ErrorScreen(message: '$e'),
      data: (state) {
        final signedIn = state.session != null;
        if (!signedIn) return const LoginScreen();

        final folderUri = ref.watch(backupFolderUriProvider);
        return folderUri.when(
          loading: () => const _Splash(),
          error: (e, _) => _ErrorScreen(message: '$e'),
          data: (uri) =>
              uri == null ? const FolderSetupScreen() : const SyncHomeScreen(),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(message)));
  }
}
