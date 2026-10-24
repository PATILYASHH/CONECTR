import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Bottom-navigation tabs, in order.
enum HomeTab { friends, backup, settings }

class HomeTabNotifier extends Notifier<HomeTab> {
  @override
  HomeTab build() {
    // A new account starts on Friends, not wherever the last one left off.
    ref.watch(currentUserIdProvider);
    return HomeTab.friends;
  }

  void select(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab>(
  HomeTabNotifier.new,
);
