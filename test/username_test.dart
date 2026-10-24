import 'package:conectr/core/profile/username.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Username.normalize', () {
    test('trims, lowercases and drops a leading @', () {
      expect(Username.normalize('  @Yash_P '), 'yash_p');
    });

    test('leaves an @ that is not leading alone, for formatError to reject',
        () {
      expect(Username.normalize('ya@sh'), 'ya@sh');
    });
  });

  group('Username.formatError', () {
    test('accepts names at both length bounds', () {
      expect(Username.formatError('abc'), isNull);
      expect(Username.formatError('a' * 20), isNull);
    });

    test('accepts letters, digits and underscore', () {
      expect(Username.formatError('yash_99'), isNull);
    });

    test('rejects names outside the length bounds', () {
      expect(Username.formatError('ab'), isNotNull);
      expect(Username.formatError('a' * 21), isNotNull);
    });

    test('rejects every character the database check rejects', () {
      for (final bad in ['ya sh', 'yash!', 'yásh', 'ya-sh', 'ya.sh', 'Yash']) {
        expect(Username.formatError(bad), isNotNull, reason: bad);
      }
    });
  });
}
