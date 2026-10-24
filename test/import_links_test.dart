import 'package:conectr/core/backup/backup_sync_service.dart';
import 'package:conectr/core/backup/import_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// The link XPENC opens (`connector_handoff.dart` there) — the two apps'
/// only contract besides the backup folder.
void main() {
  const sha = 'ce013625030ba8dba906f756967f9e9ca394464a';

  test('recognises XPENC\'s link and reads its fingerprint', () {
    final uri = Uri.parse('conectr://imported?sha=$sha');
    expect(ImportLinks.matches(uri), isTrue);
    expect(ImportLinks.shaOf(uri), sha);
  });

  test('leaves the sign-in redirect alone', () {
    expect(
      ImportLinks.matches(Uri.parse('conectr://login-callback?code=x')),
      isFalse,
    );
  });

  test('a fingerprint that isn\'t a git sha is no fingerprint', () {
    expect(ImportLinks.shaOf(Uri.parse('conectr://imported')), isNull);
    expect(ImportLinks.shaOf(Uri.parse('conectr://imported?sha=xyz')), isNull);
    expect(
      ImportLinks.shaOf(Uri.parse('conectr://imported?sha=${sha}00')),
      isNull,
    );
  });

  test('every outcome has something to say', () {
    for (final result in ImportHandoff.values) {
      expect(ImportLinks.message(result), isNotEmpty);
    }
  });
}
