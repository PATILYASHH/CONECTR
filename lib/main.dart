import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  final container = ProviderContainer();
  // Must be wired before the first OAuth redirect ever arrives — this is
  // the only moment Supabase hands back the GitHub token (see AuthService).
  container.read(authServiceProvider).listenAndPersistGithubToken();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ConectrApp(),
    ),
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
