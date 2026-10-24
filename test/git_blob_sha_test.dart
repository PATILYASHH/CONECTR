import 'dart:convert';

import 'package:conectr/core/backup/git_blob_sha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Expected values are what `git hash-object` prints for the same bytes —
  // the same sha GitHub's Contents API reports for a file.
  test('matches git for an empty file', () {
    expect(gitBlobSha(const []), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
  });

  test('matches git for "hello\\n"', () {
    expect(
      gitBlobSha(utf8.encode('hello\n')),
      'ce013625030ba8dba906f756967f9e9ca394464a',
    );
  });
}
