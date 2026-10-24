import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friends_repository.dart';

/// What to tell the user when a friends action fails.
String friendsErrorMessage(Object error) {
  return switch (error) {
    FriendRequestGoneException() => 'That request is no longer there.',
    SocketException() || http.ClientException() || TimeoutException() =>
      "Couldn't connect. Check your internet and try again.",
    PostgrestException(:final message) => 'Something went wrong: $message',
    _ => '$error',
  };
}
