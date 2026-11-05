import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/sync_lock.dart';
import '../config/app_config.dart';

/// What asking for a Supabase access token came to.
sealed class TokenResult {
  const TokenResult();
}

class HaveToken extends TokenResult {
  const HaveToken(this.accessToken, this.userId);
  final String accessToken;
  final String userId;
}

/// Nobody is signed in to Connector on this phone.
class SignedOut extends TokenResult {
  const SignedOut();
}

/// Signed in, but no token right now — offline, or Supabase unreachable.
class TokenUnavailable extends TokenResult {
  const TokenUnavailable();
}

/// Supabase access tokens for code that runs in either engine: the app's,
/// or the background job's (which has no Supabase client of its own).
///
/// A Supabase session has one refresh token, and using it twice — two
/// clients refreshing the same session — makes Supabase revoke the whole
/// session: signed out, for no visible reason. So exactly one party
/// refreshes at a time:
///
/// * while the app runs, the app's own client. The background job asks it
///   ([host] answers), and never refreshes itself;
/// * otherwise the background job, under [SyncLock.sessionName], writing
///   the new session back where supabase_flutter keeps it — and the app,
///   starting meanwhile, waits for that lock before reading it ([waitForBackgroundRefresh]).
class SessionTokens {
  static const _portName = 'connector-session';
  static ReceivePort? _host;

  /// supabase_flutter's own key for the persisted session.
  static String get _persistKey =>
      'sb-${Uri.parse(AppConfig.supabaseUrl).host.split('.').first}-auth-token';

  /// In `main`, before `Supabase.initialize` reads the session: a
  /// background refresh half-way through would otherwise hand the app the
  /// session that's just being replaced.
  static Future<void> waitForBackgroundRefresh() async {
    try {
      await SyncLock.run(
        () async {},
        lock: SyncLock.sessionName,
        wait: const Duration(seconds: 10),
      );
    } on SyncBusyException {
      // Stuck for 10 s: carry on rather than not start at all.
    }
  }

  /// In the app's isolate, after `Supabase.initialize`. Answers the
  /// background job — first "I'm here" (so it never refreshes on its own
  /// while the app runs), then the token.
  static void host() {
    if (_host != null) return;
    final port = ReceivePort()
      ..listen((message) async {
        if (message is! SendPort) return;
        message.send('here');
        message.send(_encode(await _fromApp()));
      });
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    _host = port;
  }

  /// A token good for at least a minute. In the app's isolate, from its
  /// client; elsewhere, from the app if it's running, else from storage.
  static Future<TokenResult> get() async {
    if (_host != null) return _fromApp();
    final app = IsolateNameServer.lookupPortByName(_portName);
    if (app != null) {
      final answer = await _askApp(app);
      if (answer != null) return answer;
    }
    return _fromStorage();
  }

  static Future<TokenResult> _fromApp() async {
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) return const SignedOut();
    try {
      if (_expiresSoon(session.expiresAt)) {
        session = (await auth.refreshSession()).session;
        if (session == null) return const SignedOut();
      }
    } on AuthException catch (e) {
      // A refused refresh token signs the client out by itself.
      return auth.currentSession == null || e.statusCode == '400'
          ? const SignedOut()
          : const TokenUnavailable();
    } catch (_) {
      return const TokenUnavailable();
    }
    return HaveToken(session.accessToken, session.user.id);
  }

  /// Null when the app didn't answer — it isn't running after all (a port
  /// left behind by an isolate that's gone).
  static Future<TokenResult?> _askApp(SendPort app) async {
    final reply = ReceivePort();
    final messages = StreamIterator(reply);
    try {
      app.send(reply.sendPort);
      final here = await messages.moveNext().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      if (!here) return null;
      final answered = await messages.moveNext().timeout(
        const Duration(seconds: 45),
        onTimeout: () => false,
      );
      // The app is up but slow: never refresh behind its back.
      if (!answered) return const TokenUnavailable();
      return _decode(messages.current);
    } finally {
      await messages.cancel();
      reply.close();
    }
  }

  static Future<TokenResult> _fromStorage() async {
    try {
      return await SyncLock.run(
        _refreshStored,
        lock: SyncLock.sessionName,
        wait: const Duration(seconds: 20),
      );
    } on SyncBusyException {
      return const TokenUnavailable();
    }
  }

  static Future<TokenResult> _refreshStored() async {
    final prefs = await SharedPreferences.getInstance();
    // This engine's copy may be older than what the app wrote since.
    await prefs.reload();
    final raw = prefs.getString(_persistKey);
    if (raw == null) return const SignedOut();
    final stored = jsonDecode(raw) as Map<String, dynamic>;
    final userId = (stored['user'] as Map<String, dynamic>?)?['id'] as String?;
    final access = stored['access_token'] as String?;
    final refresh = stored['refresh_token'] as String?;
    if (userId == null || access == null) return const SignedOut();
    if (!_expiresSoon(stored['expires_at'] as int?)) {
      return HaveToken(access, userId);
    }
    if (refresh == null) return const SignedOut();

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConfig.supabaseUrl}/auth/v1/token?grant_type=refresh_token',
            ),
            headers: {
              'apikey': AppConfig.supabaseAnonKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      return const TokenUnavailable();
    }
    // The session is over (signed out elsewhere, revoked). Left for the app
    // to notice and show its sign-in screen; nothing is deleted here.
    if (res.statusCode == 400 || res.statusCode == 401) {
      return const SignedOut();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return const TokenUnavailable();
    }
    final session = Session.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    if (session == null) return const TokenUnavailable();
    // Where, and how, supabase_flutter keeps it — the app picks it up as
    // its own on its next start.
    await prefs.setString(_persistKey, jsonEncode(session.toJson()));
    return HaveToken(session.accessToken, session.user.id);
  }

  static bool _expiresSoon(int? expiresAtSeconds) {
    if (expiresAtSeconds == null) return true;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtSeconds * 1000,
      isUtc: true,
    );
    return expiresAt.isBefore(
      DateTime.now().toUtc().add(const Duration(minutes: 2)),
    );
  }

  static List<String> _encode(TokenResult result) => switch (result) {
    HaveToken(:final accessToken, :final userId) => ['ok', accessToken, userId],
    SignedOut() => ['signedOut'],
    TokenUnavailable() => ['unavailable'],
  };

  static TokenResult _decode(Object? message) {
    if (message is! List || message.isEmpty) return const TokenUnavailable();
    return switch (message.first) {
      'ok' when message.length == 3 => HaveToken(
        message[1] as String,
        message[2] as String,
      ),
      'signedOut' => const SignedOut(),
      _ => const TokenUnavailable(),
    };
  }
}
