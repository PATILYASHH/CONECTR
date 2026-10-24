import 'package:flutter/material.dart';

import '../../core/friends/friends_failure.dart';

/// Runs a friends action and shows [done] — or what went wrong — as a
/// snack bar.
Future<void> runFriendsAction(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String? message = done;
  try {
    await action();
  } catch (e) {
    message = friendsErrorMessage(e);
  }
  if (message == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
