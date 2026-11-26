import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../connections/connections_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../friends/friends_controller.dart';
import '../friends/friends_screen.dart';
import '../friends/shared_sync_runner.dart';
import '../settings/settings_screen.dart';
import '../sync/backup_controller.dart';
import 'home_tab.dart';

/// The signed-in app: one tab per feature. Tabs stay alive in an
/// [IndexedStack], so switching never loses scroll position or state.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // XPENC may have been installed or removed meanwhile.
    ref.invalidate(xpencInstalledProvider);
    // Realtime can miss events while the app sat in the background.
    ref.read(friendsControllerProvider.notifier).refresh().ignore();
    ref.read(sharedSyncRunnerProvider)?.kick();
    // Coming back to the app counts as opening it (see checkOnOpen) — but
    // only once backup is set up (the Dashboard then keeps it alive).
    if (ref.exists(backupControllerProvider)) {
      ref.read(backupControllerProvider.notifier).checkOnOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSyncScheduleProvider);
    ref.watch(sharedSyncRunnerProvider);
    final tab = ref.watch(homeTabProvider);
    final requests = ref.watch(
      friendsControllerProvider.select((f) => f.value?.incoming.length ?? 0),
    );

    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [
          DashboardScreen(),
          FriendsScreen(),
          ConnectionsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (i) =>
            ref.read(homeTabProvider.notifier).select(HomeTab.values[i]),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: requests > 0,
              label: Text('$requests'),
              child: const Icon(Icons.people_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: requests > 0,
              label: Text('$requests'),
              child: const Icon(Icons.people),
            ),
            label: 'Friends',
          ),
          const NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'Connections',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
