import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';

import '../backup/backup_meta.dart';
import '../storage/secure_store.dart';

/// Who "this phone" is in backup metadata. The id tells phones apart even
/// when two share a name ("never pull back my own upload"); the name is
/// what other phones show ("from Galaxy S23").
class DeviceIdentity {
  DeviceIdentity(this._store);

  final SecureStore _store;

  /// Random, made once and kept for good — sign-out included (see
  /// `SecureStore.clearAll`).
  Future<String> id() async {
    final existing = await _store.getDeviceId();
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _store.setDeviceId(id);
    return id;
  }

  Future<String> name() async => await _store.getDeviceName() ?? defaultName();

  /// The name from the phone's own Settings → About (e.g. "Galaxy S23"),
  /// falling back to the model — which on Samsung is a code like
  /// "SM-S911B", hence not the first choice.
  Future<String> defaultName() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return BackupMeta.cleanDeviceName(
      info.name.trim().isNotEmpty ? info.name : info.model,
    );
  }

  Future<void> rename(String name) =>
      _store.setDeviceName(BackupMeta.cleanDeviceName(name));
}
