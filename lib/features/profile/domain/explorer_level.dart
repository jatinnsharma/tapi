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

  /// Beyond the last tier, one more level for every this much XP.
  static const int _xpPerLevelAtTop = 1000;

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

  /// The band of levels [xp] falls in: from its tier's first level to the
  /// next tier's, with the XP each level in between takes. Levels follow
  /// the tier table, so "Level 5" is always "Explorer" (1,000 XP).
  static ({int level, int levelXp, int xpPerLevel}) _band(int xp) {
    final safe = xp < 0 ? 0 : xp;
    for (var i = 0; i < _tiers.length - 1; i++) {
      final from = _tiers[i], to = _tiers[i + 1];
      if (safe < to.xpForLevel) {
        final per =
            (to.xpForLevel - from.xpForLevel) ~/ (to.level - from.level);
        final steps = (safe - from.xpForLevel) ~/ per;
        return (
          level: from.level + steps,
          levelXp: from.xpForLevel + steps * per,
          xpPerLevel: per,
        );
      }
    }
    final top = _tiers.last;
    final steps = (safe - top.xpForLevel) ~/ _xpPerLevelAtTop;
    return (
      level: top.level + steps,
      levelXp: top.xpForLevel + steps * _xpPerLevelAtTop,
      xpPerLevel: _xpPerLevelAtTop,
    );
  }

  /// The level number for [xp], consistent with the tier titles.
  static int levelNumberForXp(int xp) => _band(xp).level;

  /// XP earned since the current level began.
  static int xpIntoCurrentLevel(int xp) =>
      (xp < 0 ? 0 : xp) - _band(xp).levelXp;

  /// XP the current level takes in all (grows with the tiers).
  static int xpForNextLevel(int xp) => _band(xp).xpPerLevel;

  /// The one meter on You: the rank [xp] is at, the next rank, how far
  /// along the way to it (0–1), and the XP still to go. [next] is null at
  /// the top rank (progress 1).
  static ({
    ExplorerLevel current,
    ExplorerLevel? next,
    double progress,
    int xpToNext,
  })
  rankProgress(int xp) {
    final safe = xp < 0 ? 0 : xp;
    final current = forXp(safe);
    final i = _tiers.indexOf(current);
    if (i == _tiers.length - 1) {
      return (current: current, next: null, progress: 1, xpToNext: 0);
    }
    final next = _tiers[i + 1];
    final span = next.xpForLevel - current.xpForLevel;
    return (
      current: current,
      next: next,
      progress: (safe - current.xpForLevel) / span,
      xpToNext: next.xpForLevel - safe,
    );
  }
}
