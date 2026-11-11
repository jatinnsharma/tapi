import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/data/adventure_repository.dart';
import '../../tracking/domain/adventure_session.dart';
import '../domain/explorer_level.dart';

class UserStats {
  const UserStats({
    required this.totalXp,
    required this.completedAdventureCount,
    required this.totalDistanceKm,
    required this.recentAdventures,
    this.totalTrekSteps = 0,
  });

  final int totalXp;
  final int completedAdventureCount;
  final double totalDistanceKm;

  /// Steps on the trek of counted trips (step sensor).
  final int totalTrekSteps;
  final List<AdventureSession> recentAdventures;

  int get levelNumber => ExplorerLevel.levelNumberForXp(totalXp);
  String get levelTitle => ExplorerLevel.forXp(totalXp).title;
  int get xpIntoLevel => ExplorerLevel.xpIntoCurrentLevel(totalXp);
  int get xpForNextLevel => ExplorerLevel.xpForNextLevel();
  double get levelProgress =>
      xpForNextLevel == 0 ? 0 : xpIntoLevel / xpForNextLevel;
}

final userProfileProvider = FutureProvider.autoDispose<UserStats>((ref) async {
  final repository = ref.watch(adventureRepositoryProvider);

  final totalXp = await repository.getTotalXp();
  final completedAdventures = await repository.getCompletedAdventures();
  final recentAdventures = await repository.getRecentAdventures(limit: 5);

  final totalDistanceKm =
      completedAdventures.fold<double>(
        0,
        // Trek distance only; the journey isn't activity.
        (sum, adventure) => sum + adventure.trekMeters,
      ) /
      1000;

  return UserStats(
    totalXp: totalXp,
    completedAdventureCount: completedAdventures.length,
    totalDistanceKm: totalDistanceKm,
    recentAdventures: recentAdventures,
    totalTrekSteps: completedAdventures.fold<int>(
      0,
      (sum, adventure) => sum + adventure.trekSteps,
    ),
  );
});
