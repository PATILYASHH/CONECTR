import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../exocloud/exocloud_api.dart';
import '../exocloud/exocloud_backup_store.dart';
import '../exocloud/exocloud_crypto.dart';
import '../github/github_api.dart';
import '../google/drive_api.dart';
import '../google/drive_backup_store.dart';
import '../google/google_auth.dart';
import '../storage/secure_store.dart';
import 'backup_store.dart';
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
      BackupConflictException() => const SyncFailure(
        'Another phone backed up at the same moment. Sync again.',
        transient: true,
      ),
      // Google Drive.
      DriveNotAuthorizedException() ||
      DriveApiException(statusCode: 401) => const SyncFailure(
        'Google Drive access was revoked or has expired. Reconnect Google '
        'Drive.',
        needsReconnect: true,
      ),
      DriveApiException(reason: 'storageQuotaExceeded') => const SyncFailure(
        'Your Google Drive is full. Free up space to keep backing up.',
      ),
      DriveApiException(:final statusCode, :final reason)
          when statusCode == 429 ||
              reason == 'rateLimitExceeded' ||
              reason == 'userRateLimitExceeded' =>
        const SyncFailure(
          'Google Drive is rate-limiting requests.',
          transient: true,
        ),
      DriveApiException(:final statusCode) when statusCode >= 500 =>
        const SyncFailure('Google Drive is having trouble.', transient: true),
      DriveApiException(:final message) => SyncFailure(
        'Google Drive error: $message',
      ),
      GoogleNotConfiguredException() => const SyncFailure(
        "Google Drive isn't available in this version of Connector.",
      ),
      // ExoCloud.
      ExoCloudOfflineException() => const SyncFailure(
        "Couldn't reach ExoCloud. Check your connection.",
        transient: true,
      ),
      ExoCloudDecryptException() => const SyncFailure(
        "This phone's recovery key doesn't open your ExoCloud backups. "
        'Enter the right one in Settings → Backup.',
      ),
      ExoCloudApiException(:final statusCode, :final message)
          when statusCode == 413 ||
              message.toLowerCase().contains('maximum allowed size') =>
        const SyncFailure(
          'This backup is bigger than ExoCloud allows (10 MB).',
        ),
      ExoCloudApiException(:final statusCode) when statusCode >= 500 =>
        const SyncFailure('ExoCloud is having trouble.', transient: true),
      ExoCloudApiException(:final message) => SyncFailure(
        'ExoCloud error: $message',
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
        "Couldn't reach your backup. Check your connection.",
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

  /// Only reconnecting the destination (GitHub, Google Drive) fixes it —
  /// the XPENC page offers that button.
  final bool needsReconnect;

  /// Likely to fix itself (no network, a server hiccup): retried quietly on
  /// the next run instead of alarming anyone.
  final bool transient;
}
