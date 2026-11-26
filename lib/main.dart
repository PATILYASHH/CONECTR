import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/background/auto_sync.dart';
import 'core/backup/sync_state_signal.dart';
import 'core/notifications/app_notifications.dart';
import 'core/platform/xpenc_launcher.dart';
import 'core/shared/session_tokens.dart';
import 'core/config/app_config.dart';
import 'core/providers.dart';
import 'core/theme/theme_mode.dart';
import 'features/friends/friends_cache.dart';
import 'features/sync/import_link_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  // A background refresh of the session half-way through would hand
  // Supabase the session that's just being replaced (see SessionTokens).
  await SessionTokens.waitForBackgroundRefresh();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await AutoSyncScheduler.initialize();
  // Before anything can change sync state: the dashboard hears about every
  // change from here on, the background job's included.
  SyncStateSignal.listen();
  // From here on the app's client is the only one refreshing the session;
  // the background job asks it for tokens.
  SessionTokens.host();
  await AppNotifications.initForApp(
    openXpenc: () => XpencLauncher.open().ignore(),
  );

  final themeMode = await loadThemeMode();
  final container = ProviderContainer(
    overrides: [initialThemeModeProvider.overrideWithValue(themeMode)],
  );
  // Must be wired before the first OAuth redirect ever arrives — this is
  // the only moment Supabase hands back the GitHub token (see AuthService).
  container
      .read(authServiceProvider)
      .listenAndPersistGithubToken(
        onSaved: () => container
          ..invalidate(githubTokenProvider)
          ..invalidate(githubLoginProvider),
      );
  listenForImportLinks(container);
  shareFriendsWithXpenc(container);

  runApp(
    UncontrolledProviderScope(container: container, child: const ConectrApp()),
  );
}

/// Fails loudly instead of silently pointing at a broken backend — same
/// philosophy as XPENC's own `databaseReadyProvider` (see its structure.md).
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Missing SUPABASE_URL / SUPABASE_ANON_KEY.\n\n'
              'Run with:\n'
              'flutter run --dart-define-from-file=dart_define.local.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
