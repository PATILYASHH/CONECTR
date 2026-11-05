import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

/// "Sync state changed" — from whichever isolate changed it to the app's.
///
/// The background job runs in its own engine, in the same process as the
/// app when the app is open. Without this the dashboard kept showing what
/// it last read — say, a "Reconnect GitHub" problem the background job had
/// long since cleared — until the next tap. The [IsolateNameServer]
/// registry is shared by both engines (see `SyncLock`).
class SyncStateSignal {
  static const _name = 'connector-sync-state';

  static ReceivePort? _port;
  static final _changes = StreamController<void>.broadcast();

  /// Fires in the app's isolate after any sync state change, its own
  /// included. Only once [listen] has run there.
  static Stream<void> get changes => _changes.stream;

  /// Once, in `main`. Replaces whatever an earlier run of the app left
  /// registered — a port that died with its isolate still holds the name.
  static void listen() {
    if (_port != null) return;
    final port = ReceivePort()..listen((_) => _changes.add(null));
    IsolateNameServer.removePortNameMapping(_name);
    IsolateNameServer.registerPortWithName(port.sendPort, _name);
    _port = port;
  }

  /// Safe from any isolate, and a no-op when the app isn't running.
  static void notify() => IsolateNameServer.lookupPortByName(_name)?.send(null);
}
