import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/challenges/application/streak_service.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdventureRepository implements AdventureRepository {
  _FakeAdventureRepository(this._completed);

  final List<AdventureSession> _completed;

  @override
  Future<List<AdventureSession>> getCompletedAdventures() async => _completed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdventureSession _makeTrip(DateTime at) {
  return AdventureSession(
    id: 'trip-${at.millisecondsSinceEpoch}',
    title: 'Trip',
    startedAt: at,
    endedAt: at.add(const Duration(hours: 1)),
    status: AdventureStatus.completed,
    trekMeters: 500,
    durationSeconds: 1800,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StreakService', () {
    test('streak is 0 when there are no completed adventures', () async {
      final repo = _FakeAdventureRepository([]);
      final service = StreakService(repo);

      final data = await service.getStreakData();
      expect(data.currentStreak, 0);
      expect(data.completedToday, isFalse);
      expect(data.freezesAvailable, 1);
    });

    test('streak is 1 when completed today', () async {
      final now = DateTime.now();
      final repo = _FakeAdventureRepository([_makeTrip(now)]);
      final service = StreakService(repo);

      final data = await service.getStreakData();
      expect(data.currentStreak, 1);
      expect(data.completedToday, isTrue);
    });

    test('streak counts consecutive days backwards', () async {
      final now = DateTime.now();
      final trips = [
        _makeTrip(now),
        _makeTrip(now.subtract(const Duration(days: 1))),
        _makeTrip(now.subtract(const Duration(days: 2))),
      ];
      final repo = _FakeAdventureRepository(trips);
      final service = StreakService(repo);

      final data = await service.getStreakData();
      expect(data.currentStreak, 3);
      expect(data.completedToday, isTrue);
      expect(data.bestStreak, 3);
    });

    test(
      'freeze is used when yesterday was missed but prior days were completed',
      () async {
        final now = DateTime.now();
        final trips = [
          // Missed yesterday, but completed day before yesterday
          _makeTrip(now.subtract(const Duration(days: 2))),
        ];
        final repo = _FakeAdventureRepository(trips);
        final service = StreakService(repo);

        final data = await service.getStreakData();
        expect(data.freezeUsedToday, isTrue);
        expect(data.freezesAvailable, 0); // 1 initial freeze consumed
        expect(data.currentStreak, 2);
      },
    );
  });
}
