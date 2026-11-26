import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'conectr.theme_mode';

/// Read once in `main` before the first frame, so the app never flashes
/// the wrong theme. Falls back to following the system.
Future<ThemeMode> loadThemeMode() async {
  try {
    final name = (await SharedPreferences.getInstance()).getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  } catch (_) {
    return ThemeMode.system;
  }
}

/// Overridden in `main` with what [loadThemeMode] found.
final initialThemeModeProvider = Provider<ThemeMode>((_) => ThemeMode.system);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // Still applied for this run; only remembering it failed.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => 'System default',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}
