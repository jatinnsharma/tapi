import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/challenges/application/daily_challenge_service.dart';
import 'package:real_world_exploration/features/challenges/domain/daily_challenge.dart';
import 'package:real_world_exploration/features/memories/data/memory_repository.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/checkpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdventureRepository implements AdventureRepository {
  _FakeAdventureRepository();

  final List<AdventureSession> adventures = const [];
  final List<Checkpoint> checkpoints = const [];
  final List<int> recordedXp = [];

  @override
  Future<List<AdventureSession>> getAdventuresBetween(
    DateTime start,
    DateTime end,
  ) async {
    return adventures
        .where((a) => a.startedAt.isAfter(start) && a.startedAt.isBefore(end))
        .toList();
  }

  @override
  Future<List<Checkpoint>> getCheckpoints(String adventureId) async =>
      checkpoints;

  @override
  Future<void> recordXp({
    String? adventureId,
    required int amount,
    required String reason,
  }) async {
    recordedXp.add(amount);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMemoryRepository implements MemoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DailyChallengeService', () {
    test('deterministic challenge rotation by date', () {
      final service = DailyChallengeService(
        _FakeAdventureRepository(),
        _FakeMemoryRepository(),
      );

      final day1 = DateTime(2026, 10, 16);
      final day2 = DateTime(2026, 10, 17);

      final ch1 = service.getChallengeForDate(day1);
      final ch1Again = service.getChallengeForDate(day1);
      final ch2 = service.getChallengeForDate(day2);

      expect(ch1.id, ch1Again.id);
      expect(ch1.title, ch1Again.title);
      expect(ch1.id, isNot(ch2.id));
    });

    test('claim reward marks challenge claimed and awards XP', () async {
      final advRepo = _FakeAdventureRepository();
      final service = DailyChallengeService(advRepo, _FakeMemoryRepository());

      const progress = DailyChallengeProgress(
        challenge: DailyChallenge(
          id: 'test-ch',
          title: 'Test Challenge',
          description: 'Description',
          type: ChallengeType.morningWalk,
          targetValue: 1,
          xpReward: 50,
        ),
        currentValue: 1,
        isCompleted: true,
        isClaimed: false,
      );

      final success = await service.claimReward(progress);
      expect(success, isTrue);
      expect(advRepo.recordedXp, [50]);

      // Cannot claim again
      final progressClaimed = progress.copyWith(isClaimed: true);
      final secondAttempt = await service.claimReward(progressClaimed);
      expect(secondAttempt, isFalse);
    });
  });
}
