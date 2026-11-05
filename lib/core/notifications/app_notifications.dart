import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../backup/backup_meta.dart';
import '../shared/shared_entry.dart';

/// The two things worth interrupting someone for: a newer backup arrived
/// from another phone, or backup stopped working. Successful uploads stay
/// silent. Usable from the background job, so it initializes itself.
class AppNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _newBackupId = 1;
  static const _problemId = 2;

  /// Tapping a friend's entry opens XPENC, where it's answered.
  static const openXpencPayload = 'open-xpenc';

  static Future<void> _init({
    void Function(NotificationResponse)? onTap,
  }) async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
    _ready = true;
  }

  /// In the app's `main`: taps on [openXpencPayload] notifications run
  /// [openXpenc] — whether the tap started the app or found it running.
  static Future<void> initForApp({required void Function() openXpenc}) async {
    await _init(
      onTap: (response) {
        if (response.payload == openXpencPayload) openXpenc();
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if ((launch?.didNotificationLaunchApp ?? false) &&
        launch?.notificationResponse?.payload == openXpencPayload) {
      openXpenc();
    }
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

  /// A friend shared an entry, or changed one, and it waits for an answer.
  static Future<void> sharedEntry(SharedEntry entry, String? fromUsername) {
    final who = fromUsername == null ? 'A friend' : '@$fromUsername';
    final amount = _money(entry.amountMinor, entry.currency);
    // From the friend's side: owed_to is the friend when *I* owe.
    final iOwe = entry.owedTo == entry.createdBy;
    final what = entry.isOpening
        ? 'Opening balance: ${iOwe ? 'you owe' : 'they owe you'} $amount'
        : iOwe
        ? 'You owe $amount'
        : 'They owe you $amount';
    final note = entry.note?.trim();
    return _show(
      // One notification per entry; a later edit replaces it.
      1000 + entry.id.hashCode.abs() % 100000,
      '$who shared an entry',
      '$what${note == null || note.isEmpty ? '' : ' · $note'}. Open XPENC to '
          'accept or reject it.',
      channel: 'friends',
      channelName: 'Friends',
      channelDescription: 'Entries your friends share with you',
      payload: openXpencPayload,
    );
  }

  static String _money(int minor, String currency) {
    try {
      return NumberFormat.simpleCurrency(name: currency).format(minor / 100);
    } catch (_) {
      return '$currency ${(minor / 100).toStringAsFixed(2)}';
    }
  }

  static Future<void> _show(
    int id,
    String title,
    String body, {
    String channel = 'backups',
    String channelName = 'Backups',
    String channelDescription =
        'New backups from your other phones, and backup problems',
    String? payload,
  }) async {
    await _init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          channelName,
          channelDescription: channelDescription,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }
}
