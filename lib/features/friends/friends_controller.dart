import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/friends/friendship.dart';
import '../../core/friends/friends_repository.dart';
import '../../core/profile/profile_repository.dart';
import '../../core/providers.dart';

/// The Friends tab's lists, kept live by a Realtime subscription for as
/// long as the signed-in session. Actions throw; the screen shows the
/// message (see `friendsErrorMessage`).
class FriendsController extends AsyncNotifier<FriendsOverview> {
  FriendsRepository get _repo => ref.read(friendsRepositoryProvider);

  @override
  Future<FriendsOverview> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const FriendsOverview(myId: '');
    final stop = _repo.watch(userId, _reloadQuietly);
    ref.onDispose(stop);
    return FriendsOverview.from(await _repo.fetchAll(), userId);
  }

  Future<void> refresh() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final rows = await _repo.fetchAll();
    if (!ref.mounted) return;
    state = AsyncData(FriendsOverview.from(rows, userId));
  }

  /// For pushes from Realtime: a failed re-read keeps what's on screen
  /// rather than replacing it with an error.
  void _reloadQuietly() => refresh().catchError((Object _) {});

  Future<Profile?> findUser(String username) => _repo.findUser(username);

  Future<void> sendRequest(Profile to) async {
    await _repo.sendRequest(to.id);
    await refresh();
  }

  Future<void> respond(FriendLink request, {required bool accept}) async {
    try {
      await _repo.respond(request.friendshipId, accept: accept);
    } finally {
      // Gone or not, the list should stop showing the old state.
      await refresh();
    }
  }

  /// Cancels a sent request, or unfriends.
  Future<void> remove(FriendLink link) async {
    await _repo.remove(link.friendshipId);
    await refresh();
  }
}

final friendsControllerProvider =
    AsyncNotifierProvider<FriendsController, FriendsOverview>(
      FriendsController.new,
    );
