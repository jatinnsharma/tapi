import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/profile/domain/explorer_level.dart';

void main() {
  test('each rank starts at the level its table gives', () {
    const starts = {
      0: (1, 'Beginner'),
      1000: (5, 'Explorer'),
      2500: (10, 'Adventurer'),
      6000: (20, 'Pathfinder'),
      12000: (30, 'Trailblazer'),
      25000: (50, 'Expedition Leader'),
      50000: (75, 'Legendary Explorer'),
    };
    starts.forEach((xp, expected) {
      expect(ExplorerLevel.levelNumberForXp(xp), expected.$1, reason: '$xp');
      expect(ExplorerLevel.forXp(xp).title, expected.$2, reason: '$xp');
    });
  });

  test('levels never run ahead of their rank (no "Level 11 · Explorer")', () {
    for (var xp = 0; xp <= 60000; xp += 50) {
      final level = ExplorerLevel.levelNumberForXp(xp);
      final rank = ExplorerLevel.forXp(xp);
      final nextRankLevel = switch (rank.title) {
        'Beginner' => 5,
        'Explorer' => 10,
        'Adventurer' => 20,
        'Pathfinder' => 30,
        'Trailblazer' => 50,
        'Expedition Leader' => 75,
        _ => 1 << 30,
      };
      expect(level, greaterThanOrEqualTo(rank.level), reason: '$xp');
      expect(level, lessThan(nextRankLevel), reason: '$xp');
    }
  });

  test('progress within a level adds up', () {
    // Beginner: 1,000 XP over 4 levels = 250 XP per level.
    expect(ExplorerLevel.levelNumberForXp(600), 3);
    expect(ExplorerLevel.xpIntoCurrentLevel(600), 100);
    expect(ExplorerLevel.xpForNextLevel(600), 250);
    // Past the top tier: a level every 1,000 XP.
    expect(ExplorerLevel.levelNumberForXp(52500), 77);
    expect(ExplorerLevel.xpIntoCurrentLevel(52500), 500);
    expect(ExplorerLevel.xpForNextLevel(52500), 1000);
    // Negative XP (a bad stored value) is treated as none.
    expect(ExplorerLevel.levelNumberForXp(-5), 1);
    expect(ExplorerLevel.xpIntoCurrentLevel(-5), 0);
  });
}
