import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/profile/domain/rank_style.dart';

void main() {
  test('styles sit at the same XP as the ranks', () {
    expect(stylesMatchRanks(), true);
  });

  test('styles go up in XP and the first is free', () {
    expect(rankStyles.first.minXp, 0);
    for (var i = 1; i < rankStyles.length; i++) {
      expect(rankStyles[i].minXp, greaterThan(rankStyles[i - 1].minXp));
    }
  });

  test('XP unlocks styles at their threshold', () {
    expect(highestUnlocked(0).title, 'Beginner');
    expect(highestUnlocked(999).title, 'Beginner');
    expect(highestUnlocked(1000).title, 'Explorer');
    expect(highestUnlocked(999999).title, 'Legendary Explorer');
  });

  test('an equipped style that is unlocked stays', () {
    expect(resolveStyle('Beginner', 3000).title, 'Beginner');
    expect(resolveStyle('Adventurer', 3000).title, 'Adventurer');
  });

  test(
    'a locked or unknown equipped style falls back to the best unlocked',
    () {
      expect(resolveStyle('Legendary Explorer', 3000).title, 'Adventurer');
      expect(resolveStyle('nonsense', 1200).title, 'Explorer');
      expect(resolveStyle(null, 0).title, 'Beginner');
    },
  );

  test('nextLocked finds the next reward, and none at the top', () {
    expect(nextLocked(0)?.title, 'Explorer');
    expect(nextLocked(2500)?.title, 'Pathfinder');
    expect(nextLocked(50000), isNull);
  });
}
