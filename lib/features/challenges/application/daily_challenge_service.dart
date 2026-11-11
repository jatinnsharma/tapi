import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../memories/data/memory_repository.dart';
import '../../tracking/data/adventure_repository.dart';
import '../domain/daily_challenge.dart';

final dailyChallengeServiceProvider = Provider<DailyChallengeService>((ref) {
  return DailyChallengeService(
    ref.watch(adventureRepositoryProvider),
    ref.watch(memoryRepositoryProvider),
  );
});

final todayChallengeProgressProvider = FutureProvider<DailyChallengeProgress>((
  ref,
) {
  return ref.watch(dailyChallengeServiceProvider).getTodayProgress();
});

class DailyChallengeService {
  DailyChallengeService(this._adventureRepo, this._memoryRepo);

  final AdventureRepository _adventureRepo;
  final MemoryRepository _memoryRepo;

  static const List<DailyChallenge> _catalog = [
    DailyChallenge(
      id: 'dc-1',
      title: 'Morning Explorer',
      description: 'Finish a counted adventure before 11:00 AM.',
      type: ChallengeType.morningWalk,
      targetValue: 1,
      xpReward: 50,
    ),
    DailyChallenge(
      id: 'dc-2',
      title: 'Trek Trailblazer',
      description: 'Walk at least 1,500 meters of trek on foot today.',
      type: ChallengeType.trekDistance,
      targetValue: 1500,
      xpReward: 60,
    ),
    DailyChallenge(
      id: 'dc-3',
      title: 'Garden Wanderer',
      description: 'Reach a park or garden destination on foot.',
      type: ChallengeType.visitCategory,
      targetCategory: 'garden',
      targetValue: 1,
      xpReward: 50,
    ),
    DailyChallenge(
      id: 'dc-4',
      title: 'City Documenter',
      description: 'Capture at least one memory photo during an adventure.',
      type: ChallengeType.snapPhoto,
      targetValue: 1,
      xpReward: 40,
    ),
    DailyChallenge(
      id: 'dc-5',
      title: 'Distance Hero',
      description: 'Walk at least 2,500 meters on trek today.',
      type: ChallengeType.trekDistance,
      targetValue: 2500,
      xpReward: 75,
    ),
    DailyChallenge(
      id: 'dc-6',
      title: 'Scenic View',
      description: 'Reach a lake or viewpoint destination.',
      type: ChallengeType.visitCategory,
      targetCategory: 'viewpoint',
      targetValue: 1,
      xpReward: 60,
    ),
  ];

  DailyChallenge getChallengeForDate(DateTime date) {
    final daysSinceEpoch = date.difference(DateTime(2026, 1, 1)).inDays.abs();
    return _catalog[daysSinceEpoch % _catalog.length];
  }

  Future<DailyChallengeProgress> getTodayProgress() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final challenge = getChallengeForDate(today);

    final prefs = await SharedPreferences.getInstance();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    final isClaimed =
        prefs.getBool('challenge_claimed_${challenge.id}_$todayStr') ?? false;

    final todayAdventures = await _adventureRepo.getAdventuresBetween(
      today,
      tomorrow,
    );
    final completedAdventures = todayAdventures
        .where((a) => a.isCompleted)
        .toList();

    var currentValue = 0;
    switch (challenge.type) {
      case ChallengeType.trekDistance:
        final totalTrekMeters = completedAdventures.fold<double>(
          0.0,
          (sum, a) => sum + a.trekMeters,
        );
        currentValue = totalTrekMeters.round();
        break;

      case ChallengeType.morningWalk:
        final morningTrips = completedAdventures.where((a) {
          final hour = a.endedAt?.toLocal().hour ?? a.startedAt.toLocal().hour;
          return hour < 11;
        }).length;
        currentValue = morningTrips;
        break;

      case ChallengeType.visitCategory:
        var matchingCheckpoints = 0;
        for (final adv in completedAdventures) {
          final checkpoints = await _adventureRepo.getCheckpoints(adv.id);
          if (checkpoints.any((c) => c.isReached)) {
            matchingCheckpoints++;
          }
        }
        currentValue = matchingCheckpoints;
        break;

      case ChallengeType.snapPhoto:
        final memories = await _memoryRepo.getAll();
        final todayMemories = memories.where((m) {
          final d = m.timestamp.toLocal();
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        }).length;
        currentValue = todayMemories;
        break;

      case ChallengeType.newPlace:
        currentValue = completedAdventures.length;
        break;
    }

    final isCompleted = currentValue >= challenge.targetValue;

    return DailyChallengeProgress(
      challenge: challenge,
      currentValue: currentValue,
      isCompleted: isCompleted,
      isClaimed: isClaimed,
    );
  }

  Future<bool> claimReward(DailyChallengeProgress progress) async {
    if (!progress.isCompleted || progress.isClaimed) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = '${today.year}-${today.month}-${today.day}';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'challenge_claimed_${progress.challenge.id}_$todayStr',
      true,
    );

    await _adventureRepo.recordXp(
      amount: progress.challenge.xpReward,
      reason: 'Daily Challenge: ${progress.challenge.title}',
    );

    return true;
  }
}
