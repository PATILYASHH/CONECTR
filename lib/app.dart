import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/widgets/status_screens.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/profile/username_screen.dart';

/// For messages from outside any screen — the answer to XPENC's "Tell
/// Connector" link (see `import_link_handler.dart`).
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// For opening a page from outside any screen — the same link opens
/// XPENC's connection page.
final appNavigatorKey = GlobalKey<NavigatorState>();

class ConectrApp extends ConsumerWidget {
  const ConectrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      navigatorKey: appNavigatorKey,
      title: 'Connector',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      home: const _Gate(),
    );
  }
}

/// Checked in order: signed in? picked a username? GitHub and the backup
/// folder are asked for later, on XPENC's connection page (`BackupGate`) — an
/// email account gets in without ever touching GitHub.
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
          data: (p) => p == null ? const UsernameScreen() : const HomeShell(),
        );
      },
    );
  }
}
