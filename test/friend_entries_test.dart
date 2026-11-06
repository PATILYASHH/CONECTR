import 'package:conectr/features/friends/shared_sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a friend's sheet and tile show, from the `shared.json` a sync
/// leaves.
void main() {
  Map<String, dynamic> entry({
    String friendId = 'ana',
    bool byMe = true,
    bool theyOwe = true,
    int amountMinor = 50000,
    String currency = 'INR',
    String date = '2026-11-05',
    String status = 'accepted',
  }) => {
    'id': 'e-$date-$amountMinor',
    'friendId': friendId,
    'byMe': byMe,
    'theyOwe': theyOwe,
    'amountMinor': amountMinor,
    'currency': currency,
    'date': date,
    'note': null,
    'isOpening': false,
    'status': status,
    'version': 1,
    'updatedAt': '${date}T10:00:00Z',
  };

  Map<String, dynamic> snapshot(List<Map<String, dynamic>> entries) => {
    'version': 1,
    'signedIn': true,
    'me': 'me',
    'entries': entries,
  };

  test('groups by friend, newest first', () {
    final byFriend = entriesByFriend(
      snapshot([
        entry(date: '2026-11-01'),
        entry(friendId: 'raj', date: '2026-11-02'),
        entry(date: '2026-11-05'),
      ]),
      'me',
    );

    expect(byFriend.keys, unorderedEquals(['ana', 'raj']));
    expect(byFriend['ana']!.map((e) => e.date), ['2026-11-05', '2026-11-01']);
  });

  test('the balance counts accepted entries only, per currency', () {
    final entries = entriesByFriend(
      snapshot([
        entry(amountMinor: 50000),
        entry(theyOwe: false, amountMinor: 20000),
        entry(amountMinor: 99900, status: 'pending'),
        entry(amountMinor: 1000, status: 'rejected'),
        entry(theyOwe: false, amountMinor: 1250, currency: 'USD'),
      ]),
      'me',
    )['ana']!;

    expect(netOf(entries), {'INR': 30000, 'USD': -1250});
    expect(balanceLabel(netOf(entries)), contains('Owes you'));
    expect(balanceLabel(netOf(entries)), contains('You owe'));
  });

  test('square is no label', () {
    final entries = entriesByFriend(
      snapshot([entry(), entry(theyOwe: false)]),
      'me',
    )['ana']!;

    expect(balanceLabel(netOf(entries)), isNull);
  });

  test('who has to answer', () {
    final entries = entriesByFriend(
      snapshot([
        entry(byMe: false, status: 'pending'),
        entry(byMe: true, status: 'pending', date: '2026-11-04'),
      ]),
      'me',
    )['ana']!;

    expect(entries.where((e) => e.toAnswer).length, 1);
    expect(entries.where((e) => e.waitingOnThem).length, 1);
  });

  test("nothing from a signed-out snapshot, or another account's", () {
    expect(
      entriesByFriend({
        ...snapshot([entry()]),
        'signedIn': false,
      }, 'me'),
      isEmpty,
    );
    expect(entriesByFriend(snapshot([entry()]), 'someone-else'), isEmpty);
    expect(entriesByFriend(snapshot([entry()]), null), isEmpty);
    expect(entriesByFriend(null, 'me'), isEmpty);
  });

  test('an unreadable row is skipped, not fatal', () {
    final byFriend = entriesByFriend(
      snapshot([
        entry(),
        {'friendId': 'ana', 'amountMinor': 'lots'},
      ]),
      'me',
    );

    expect(byFriend['ana'], hasLength(1));
  });
}
