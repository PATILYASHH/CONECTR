import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The sha git (and so GitHub's Contents API) assigns to a file with these
/// exact bytes. Comparing it with the remote file's `sha` tells whether an
/// upload would change anything, without downloading the remote file.
String gitBlobSha(List<int> bytes) {
  final header = utf8.encode('blob ${bytes.length}\u0000');
  return sha1.convert([...header, ...bytes]).toString();
}
