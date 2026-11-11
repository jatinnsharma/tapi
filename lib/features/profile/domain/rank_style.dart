import 'package:flutter/material.dart';

import 'explorer_level.dart';

/// What reaching a rank gives you: a profile frame and a trail colour for the
/// route you walk. Unlocked by total XP, equipped by you.
class RankStyle {
  const RankStyle({
    required this.title,
    required this.minXp,
    required this.frame,
    required this.trail,
  });

  /// Matches the [ExplorerLevel] tier with the same XP threshold.
  final String title;
  final int minXp;

  /// Colours of the ring around your avatar.
  final List<Color> frame;

  /// Colour of the path you walk on the trip map.
  final Color trail;

  String get id => title;

  bool isUnlocked(int totalXp) => totalXp >= minXp;
}

const rankStyles = [
  RankStyle(
    title: 'Beginner',
    minXp: 0,
    frame: [Color(0xFFFFFFFF), Color(0xFFB7E4C7)],
    trail: Color(0xFFF5A623),
  ),
  RankStyle(
    title: 'Explorer',
    minXp: 1000,
    frame: [Color(0xFFCD7F32), Color(0xFFE9B681)],
    trail: Color(0xFF2E86DE),
  ),
  RankStyle(
    title: 'Adventurer',
    minXp: 2500,
    frame: [Color(0xFF9EA7B0), Color(0xFFE3E8EC)],
    trail: Color(0xFFFF6B6B),
  ),
  RankStyle(
    title: 'Pathfinder',
    minXp: 6000,
    frame: [Color(0xFFF5B301), Color(0xFFFFE08A)],
    trail: Color(0xFF8E44AD),
  ),
  RankStyle(
    title: 'Trailblazer',
    minXp: 12000,
    frame: [Color(0xFF00C9A7), Color(0xFFF5B301), Color(0xFF2E86DE)],
    trail: Color(0xFFE91E8C),
  ),
  RankStyle(
    title: 'Expedition Leader',
    minXp: 25000,
    frame: [Color(0xFFFF512F), Color(0xFFF5B301)],
    trail: Color(0xFFFF7A00),
  ),
  RankStyle(
    title: 'Legendary Explorer',
    minXp: 50000,
    frame: [
      Color(0xFFF5B301),
      Color(0xFFFFFFFF),
      Color(0xFFF5B301),
      Color(0xFFFFE08A),
    ],
    trail: Color(0xFFFFC400),
  ),
];

/// The style with this id if [totalXp] unlocks it; otherwise the best one
/// unlocked (so lost or reset XP never leaves a locked style on).
RankStyle resolveStyle(String? equippedId, int totalXp) {
  for (final s in rankStyles) {
    if (s.id == equippedId && s.isUnlocked(totalXp)) return s;
  }
  return highestUnlocked(totalXp);
}

RankStyle highestUnlocked(int totalXp) =>
    rankStyles.lastWhere((s) => s.isUnlocked(totalXp));

/// The next style still locked, or null at the top.
RankStyle? nextLocked(int totalXp) {
  for (final s in rankStyles) {
    if (!s.isUnlocked(totalXp)) return s;
  }
  return null;
}

/// True when every style sits at the XP of the rank with the same title.
bool stylesMatchRanks() =>
    rankStyles.every((s) => ExplorerLevel.forXp(s.minXp).title == s.title);
