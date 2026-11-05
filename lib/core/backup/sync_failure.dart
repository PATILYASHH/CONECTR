import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../github/github_api.dart';
import '../storage/secure_store.dart';
import 'backup_sync_service.dart';
import 'sync_lock.dart';

/// Any sync error, sorted into what the user should see and whether it's
/// worth telling them at all.
class SyncFailure {
  const SyncFailure(
    this.message, {
    this.needsReconnect = false,
    this.transient = false,
  });

  factory SyncFailure.from(Object error) {
    return switch (error) {
      SyncSetupException(:final message) => SyncFailure(message),
      // Nothing was overwritten; the next run looks again.
      GithubConflictException() => const SyncFailure(
        'The backup on GitHub changed while uploading. Sync again.',
        transient: true,
      ),
      SyncBusyException() => const SyncFailure(
        'Another sync is still running. Try again in a moment.',
        transient: true,
      ),
      // The token checked out fine straight after; not worth a red card.
      GithubAuthGlitchException() => const SyncFailure(
        'GitHub refused a request. Sync again in a moment.',
        transient: true,
      ),
      // Nothing was lost — the keystore was only briefly unavailable.
      SecureStoreException() => const SyncFailure(
        "Couldn't read this phone's saved sign-in just now. Sync again in a "
        'moment.',
        transient: true,
      ),
      GithubApiException(statusCode: 401) => const SyncFailure(
        'GitHub access was revoked or has expired. Reconnect GitHub.',
        needsReconnect: true,
      ),
      GithubApiException(:final message)
          when message.toLowerCase().contains('rate limit') =>
        const SyncFailure('GitHub is rate-limiting requests.', transient: true),
      GithubApiException(:final statusCode) when statusCode >= 500 =>
        const SyncFailure('GitHub is having trouble.', transient: true),
      GithubApiException(:final message) => SyncFailure(
        'GitHub error: $message',
      ),
      SocketException() ||
      http.ClientException() ||
      TimeoutException() => const SyncFailure(
        "Couldn't reach GitHub. Check your connection.",
        transient: true,
      ),
      // SAF: the folder permission was revoked, or the folder is gone.
      PlatformException() => const SyncFailure(
        "Can't open the backup folder any more. Choose it again in "
        'Settings → Backup folder.',
      ),
      _ => SyncFailure('$error'),
    };
  }

  final String message;

  /// Only reconnecting GitHub fixes it — the dashboard offers that button.
  final bool needsReconnect;

  /// Likely to fix itself (no network, GitHub hiccup): retried quietly on
  /// the next run instead of alarming anyone.
  final bool transient;
}
