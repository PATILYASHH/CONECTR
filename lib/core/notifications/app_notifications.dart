import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../backup/backup_meta.dart';

/// The two things worth interrupting someone for: a newer backup arrived
/// from another phone, or backup stopped working. Successful uploads stay
/// silent. Usable from the background job, so it initializes itself.
class AppNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _newBackupId = 1;
  static const _problemId = 2;

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Android 13+ asks once; after that this is a no-op.
  static Future<void> requestPermission() async {
    await _init();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> newBackup(RemoteBackup remote) {
    return _show(
      _newBackupId,
      'New backup from ${remote.deviceName ?? 'another phone'}',
      'Open XPENC to take it in — it does by itself, or asks first if '
          'this phone has changes of its own. Backups from this phone wait '
          'until then.',
    );
  }

  static Future<void> backupPaused(String reason) {
    return _show(_problemId, 'Backup paused', reason);
  }

  static Future<void> _show(int id, String title, String body) async {
    await _init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'backups',
          'Backups',
          channelDescription:
              'New backups from your other phones, and backup problems',
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }
}
