import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/status_screens.dart';
import 'features/auth/login_screen.dart';
import 'features/profile/username_screen.dart';
import 'features/sync/backup_gate.dart';

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

/// Checked in order: signed in? picked a username? GitHub and the backup
/// folder are asked for later, by [BackupGate] — an email account gets in
/// without ever touching GitHub.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const LoadingScreen(),
      error: (e, _) => ErrorScreen(message: '$e'),
      data: (state) {
        final signedIn = state.session != null;
        if (!signedIn) return const LoginScreen();

        final profile = ref.watch(myProfileProvider);
        return profile.when(
          loading: () => const LoadingScreen(),
          error: (e, _) => ErrorScreen(
            message: "Couldn't load your profile.\n\n$e",
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
          data: (p) => p == null ? const UsernameScreen() : const BackupGate(),
        );
      },
    );
  }
}
