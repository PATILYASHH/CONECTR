import 'package:flutter/services.dart';

/// Opens XPENC so a pulled backup is one tap from "Import from file".
/// Backed by `MainActivity.kt`; the manifest's `<queries>` entry is what
/// lets Android 11+ see XPENC at all.
class XpencLauncher {
  static const _channel = MethodChannel('conectr/apps');
  static const _package = 'com.yash.xpenc';

  static Future<bool> isInstalled() async =>
      await _channel.invokeMethod<bool>('isInstalled', _package) ?? false;

  static Future<bool> open() async =>
      await _channel.invokeMethod<bool>('launch', _package) ?? false;
}
