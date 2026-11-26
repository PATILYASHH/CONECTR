import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Bottom-navigation tabs, in order.
enum HomeTab { dashboard, friends, connections, settings }

class HomeTabNotifier extends Notifier<HomeTab> {
  @override
  HomeTab build() {
    // A new account starts on the Dashboard, not wherever the last one
    // left off.
    ref.watch(currentUserIdProvider);
    return HomeTab.dashboard;
  }

  void select(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab>(
  HomeTabNotifier.new,
);
