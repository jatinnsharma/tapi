import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/social/domain/leaderboard.dart';

({String uid, String name, int xp, String? photoUrl}) _e(
  String uid,
  String name,
  int xp,
) => (uid: uid, name: name, xp: xp, photoUrl: null);

void main() {
  group('rankByXp', () {
    test('orders by XP, highest first', () {
      final ranked = rankByXp([
        _e('a', 'Asha', 200),
        _e('b', 'Bilal', 1000),
        _e('c', 'Chen', 500),
      ], myUid: 'a');
      expect([for (final e in ranked) e.uid], ['b', 'c', 'a']);
      expect([for (final e in ranked) e.rank], [1, 2, 3]);
    });

    test('gives equal XP the same rank and skips the next ("1, 2, 2, 4")', () {
      final ranked = rankByXp([
        _e('a', 'Asha', 1000),
        _e('b', 'Bilal', 500),
        _e('c', 'Chen', 500),
        _e('d', 'Dev', 200),
      ], myUid: 'z');
      expect([for (final e in ranked) e.rank], [1, 2, 2, 4]);
    });

    test('breaks ties by name so the order never jumps around', () {
      final ranked = rankByXp([
        _e('z', 'zoya', 300),
        _e('a', 'Aman', 300),
      ], myUid: 'z');
      expect([for (final e in ranked) e.displayName], ['Aman', 'zoya']);
    });

    test('marks the signed-in user', () {
      final ranked = rankByXp([
        _e('me', 'Me', 10),
        _e('x', 'Other', 20),
      ], myUid: 'me');
      expect(ranked.singleWhere((e) => e.isMe).uid, 'me');
      expect(ranked.where((e) => e.isMe), hasLength(1));
    });

    test('handles an empty list', () {
      expect(rankByXp(const [], myUid: 'me'), isEmpty);
    });
  });

  group('Leaderboard.meIsListed', () {
    const me = LeaderboardEntry(
      uid: 'me',
      displayName: 'Me',
      totalXp: 5,
      rank: 73,
      isMe: true,
    );

    test('is false when the user ranks below the listed rows', () {
      const board = Leaderboard(entries: [], me: me);
      expect(board.meIsListed, isFalse);
    });

    test('is true when the user is one of the rows', () {
      const board = Leaderboard(entries: [me], me: me);
      expect(board.meIsListed, isTrue);
    });
  });
}
