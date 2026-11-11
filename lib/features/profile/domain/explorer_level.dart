class ExplorerLevel {
  const ExplorerLevel({
    required this.level,
    required this.title,
    required this.xpForLevel,
  });

  final int level;
  final String title;
  final int xpForLevel;

  static const List<ExplorerLevel> _tiers = [
    ExplorerLevel(level: 1, title: 'Beginner', xpForLevel: 0),
    ExplorerLevel(level: 5, title: 'Explorer', xpForLevel: 1000),
    ExplorerLevel(level: 10, title: 'Adventurer', xpForLevel: 2500),
    ExplorerLevel(level: 20, title: 'Pathfinder', xpForLevel: 6000),
    ExplorerLevel(level: 30, title: 'Trailblazer', xpForLevel: 12000),
    ExplorerLevel(level: 50, title: 'Expedition Leader', xpForLevel: 25000),
    ExplorerLevel(level: 75, title: 'Legendary Explorer', xpForLevel: 50000),
  ];

  /// XP required per level within a tier, used to compute an exact level
  /// number between the named tier thresholds above.
  static const int _xpPerLevel = 100;

  static ExplorerLevel forXp(int xp) {
    var current = _tiers.first;
    for (final tier in _tiers) {
      if (xp >= tier.xpForLevel) {
        current = tier;
      } else {
        break;
      }
    }
    return current;
  }

  static int levelNumberForXp(int xp) {
    return (xp / _xpPerLevel).floor() + 1;
  }

  static int xpIntoCurrentLevel(int xp) {
    return xp % _xpPerLevel;
  }

  static int xpForNextLevel() => _xpPerLevel;
}
