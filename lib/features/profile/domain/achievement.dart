import 'package:flutter/material.dart';

/// What an achievement counts.
enum AchievementMetric {
  adventures,
  distanceKm,
  placesReached,
  placesDiscovered,
  memories,
  voiceNotes,
  trekSteps,
}

/// A tiered achievement: three stars, each earned at a higher target and
/// paying a bonus-XP reward you claim yourself.
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.icon,
    required this.metric,
    required this.targets,
    required this.unit,
    this.rewards = defaultRewardsXp,
  });

  final String id;
  final String title;
  final IconData icon;
  final AchievementMetric metric;

  /// Value needed for the bronze, silver and gold star (always three,
  /// increasing: see test/achievements_test.dart).
  final List<int> targets;

  /// What the target counts, e.g. "adventures" or "km".
  final String unit;

  /// Bonus XP for the bronze, silver and gold star.
  final List<int> rewards;

  static const defaultRewardsXp = [50, 150, 400];

  String describe(int target) => switch (metric) {
    AchievementMetric.adventures => 'Complete $target adventures',
    AchievementMetric.distanceKm => 'Trek $target km in total',
    AchievementMetric.placesReached => 'Reach $target places on trips',
    AchievementMetric.placesDiscovered => 'Discover $target places',
    AchievementMetric.memories => 'Save $target photos or videos',
    AchievementMetric.voiceNotes => 'Record $target voice notes',
    AchievementMetric.trekSteps => 'Take $target steps on treks',
  };
}

const bronzeSilverGold = ['Bronze', 'Silver', 'Gold'];

/// Most photos/videos that count toward Memory Maker from one trip.
const maxMediaPerTrip = 5;

/// Most voice notes that count toward Storyteller from one trip.
const maxVoiceNotesPerTrip = 3;

/// How many items count when each trip can contribute at most [cap]: only
/// items made on a trip in [countedTrips] (verified, completed ones) are
/// considered. Stops one gallery photo, added again and again, from farming
/// stars: more memories need more real trips.
int countCappedPerTrip(
  Iterable<String?> itemTripIds, {
  required Set<String> countedTrips,
  required int cap,
}) {
  final perTrip = <String, int>{};
  for (final id in itemTripIds) {
    if (id != null && countedTrips.contains(id)) {
      perTrip[id] = (perTrip[id] ?? 0) + 1;
    }
  }
  return perTrip.values.fold(0, (sum, n) => sum + (n > cap ? cap : n));
}

/// The achievements in version 1.
const achievementDefs = [
  AchievementDef(
    id: 'adventures',
    title: 'Trail Walker',
    icon: Icons.hiking_rounded,
    metric: AchievementMetric.adventures,
    targets: [1, 5, 20],
    unit: 'adventures',
  ),
  AchievementDef(
    id: 'distance',
    title: 'Long Walker',
    icon: Icons.route_rounded,
    metric: AchievementMetric.distanceKm,
    targets: [5, 25, 100],
    unit: 'km',
  ),
  AchievementDef(
    id: 'reached',
    title: 'Destination Hunter',
    icon: Icons.flag_rounded,
    metric: AchievementMetric.placesReached,
    targets: [3, 10, 30],
    unit: 'places',
  ),
  AchievementDef(
    id: 'discovered',
    title: 'City Explorer',
    icon: Icons.explore_rounded,
    metric: AchievementMetric.placesDiscovered,
    targets: [5, 15, 30],
    unit: 'places',
  ),
  AchievementDef(
    id: 'memories',
    title: 'Memory Maker',
    icon: Icons.photo_camera_rounded,
    metric: AchievementMetric.memories,
    targets: [3, 15, 50],
    unit: 'memories',
  ),
  AchievementDef(
    id: 'voice',
    title: 'Storyteller',
    icon: Icons.mic_rounded,
    metric: AchievementMetric.voiceNotes,
    targets: [1, 5, 15],
    unit: 'notes',
  ),
  AchievementDef(
    id: 'steps',
    title: 'Step Master',
    icon: Icons.directions_walk_rounded,
    metric: AchievementMetric.trekSteps,
    targets: [10000, 50000, 250000],
    unit: 'steps',
  ),
];

/// One achievement with the player's current value and how many stars they
/// have already claimed.
class AchievementProgress {
  const AchievementProgress({
    required this.def,
    required this.value,
    required this.claimedStars,
  });

  final AchievementDef def;

  /// Current count: adventures completed, km walked, and so on.
  final double value;

  /// Stars whose reward has been collected (0..3).
  final int claimedStars;

  /// Stars earned so far (0..3), claimed or not.
  int get earnedStars {
    var stars = 0;
    for (final target in def.targets) {
      if (value >= target) stars++;
    }
    return stars;
  }

  /// Stars earned but not yet collected.
  int get claimableStars => (earnedStars - claimedStars).clamp(0, 3);

  bool get hasClaimable => claimableStars > 0;
  bool get isMaxed => earnedStars == 3;

  /// XP waiting to be collected.
  int get claimableXp {
    var xp = 0;
    for (var i = claimedStars; i < earnedStars; i++) {
      xp += def.rewards[i];
    }
    return xp;
  }

  /// The target for the next star, or null once all three are earned.
  int? get nextTarget => isMaxed ? null : def.targets[earnedStars];

  /// 0..1 progress from the previous star's target to the next one.
  double get progressToNext {
    final next = nextTarget;
    if (next == null) return 1;
    final from = earnedStars == 0 ? 0 : def.targets[earnedStars - 1];
    return ((value - from) / (next - from)).clamp(0.0, 1.0);
  }

  /// "3 / 5" for the next target, or "Maxed out".
  String get progressLabel {
    final next = nextTarget;
    if (next == null) return 'All stars earned';
    final shown = value >= next ? next : value.floor();
    return '$shown / $next ${def.unit}';
  }
}
