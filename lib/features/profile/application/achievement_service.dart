import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../locations/data/location_repository.dart';
import '../../memories/data/memory_repository.dart';
import '../../memories/domain/memory_model.dart';
import '../../tracking/data/adventure_repository.dart';
import '../domain/achievement.dart';
import '../domain/explorer_level.dart';
import 'user_profile_service.dart';

/// What claiming gave the player, for the celebration.
class ClaimResult {
  const ClaimResult({
    required this.def,
    required this.stars,
    required this.xp,
    required this.levelBefore,
    required this.levelAfter,
  });

  final AchievementDef def;

  /// Star numbers collected, e.g. [1] or [2, 3].
  final List<int> stars;
  final int xp;
  final int levelBefore;
  final int levelAfter;

  bool get leveledUp => levelAfter > levelBefore;
}

final achievementServiceProvider = Provider<AchievementService>((ref) {
  return AchievementService(
    ref.watch(adventureRepositoryProvider),
    ref.watch(locationRepositoryProvider),
    ref.watch(memoryRepositoryProvider),
  );
});

/// Every achievement with current progress, recomputed from what's stored
/// on the phone.
final achievementsProvider =
    FutureProvider.autoDispose<List<AchievementProgress>>((ref) {
      return ref.watch(achievementServiceProvider).load();
    });

class AchievementService {
  AchievementService(this._adventures, this._locations, this._memories);

  final AdventureRepository _adventures;
  final LocationRepository _locations;
  final MemoryRepository _memories;

  static String _claimedKey(String id) => 'achievement_claimed_$id';

  Future<List<AchievementProgress>> load() async {
    final completed = await _adventures.getCompletedAdventures();
    // Trek distance only: driving to a trek doesn't count as walking.
    final km = completed.fold<double>(0, (sum, a) => sum + a.trekMeters) / 1000;
    // Counts only places confirmed by photo on trips that passed the checks.
    final reached = await _adventures.getTotalReachedCheckpoints();
    final discovered = (await _locations.getAll())
        .where((l) => l.isDiscovered)
        .length;
    final memories = await _memories.getAll(limit: 100000);
    // Only trips that passed the checks count, and only a few memories per
    // trip: see countCappedPerTrip.
    final counted = {for (final a in completed) a.id};
    final media = countCappedPerTrip(
      memories
          .where((m) => m.type != MemoryType.voiceNote)
          .map((m) => m.adventureId),
      countedTrips: counted,
      cap: maxMediaPerTrip,
    );
    final voice = countCappedPerTrip(
      memories
          .where((m) => m.type == MemoryType.voiceNote)
          .map((m) => m.adventureId),
      countedTrips: counted,
      cap: maxVoiceNotesPerTrip,
    );

    final values = <AchievementMetric, double>{
      AchievementMetric.adventures: completed.length.toDouble(),
      AchievementMetric.distanceKm: km,
      AchievementMetric.placesReached: reached.toDouble(),
      AchievementMetric.placesDiscovered: discovered.toDouble(),
      AchievementMetric.memories: media.toDouble(),
      AchievementMetric.voiceNotes: voice.toDouble(),
      // Steps on the trek of counted trips, from the phone's step sensor.
      AchievementMetric.trekSteps: completed
          .fold<int>(0, (sum, a) => sum + a.trekSteps)
          .toDouble(),
    };

    final prefs = await SharedPreferences.getInstance();
    return [
      for (final def in achievementDefs)
        AchievementProgress(
          def: def,
          value: values[def.metric] ?? 0,
          claimedStars: (prefs.getInt(_claimedKey(def.id)) ?? 0).clamp(0, 3),
        ),
    ];
  }

  /// Collects every earned, unclaimed star of [progress] and pays the XP.
  /// Returns null if there was nothing to claim. The claim is recorded
  /// before the XP is paid, so a double tap can't pay twice.
  Future<ClaimResult?> claim(AchievementProgress progress) async {
    // Re-read: the screen's copy may be stale.
    final fresh = (await load()).firstWhere((p) => p.def.id == progress.def.id);
    if (!fresh.hasClaimable) return null;

    final xp = fresh.claimableXp;
    final stars = [
      for (var i = fresh.claimedStars; i < fresh.earnedStars; i++) i + 1,
    ];
    final xpBefore = await _adventures.getTotalXp();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_claimedKey(fresh.def.id), fresh.earnedStars);

    await _adventures.recordXp(
      amount: xp,
      reason:
          'Achievement: ${fresh.def.title} '
          '${stars.map((s) => bronzeSilverGold[s - 1]).join(' + ')}',
    );

    return ClaimResult(
      def: fresh.def,
      stars: stars,
      xp: xp,
      levelBefore: ExplorerLevel.levelNumberForXp(xpBefore),
      levelAfter: ExplorerLevel.levelNumberForXp(xpBefore + xp),
    );
  }
}

/// Refresh everything that shows achievements or XP after a claim.
void refreshAfterClaim(WidgetRef ref) {
  ref.invalidate(achievementsProvider);
  ref.invalidate(userProfileProvider);
}
