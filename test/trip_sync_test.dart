// Saving a trip must never wait on the cloud. Firestore only confirms a
// write once its server has it, which never happens offline or before the
// Firestore database exists; the planner used to spin forever on that.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/data/trip_cloud_repository.dart';
import 'package:real_world_exploration/features/planner/domain/plan_merge.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cloud that never answers.
class _SilentCloud extends Fake implements TripCloudRepository {
  int saves = 0;

  @override
  Future<TripPlan> saveMerged(
    TripPlan plan, {
    TripPlan? base,
    bool savedByOwner = false,
  }) {
    saves++;
    return Completer<TripPlan>().future;
  }

  @override
  Future<List<TripPlan>> getTripsFor(String uid) =>
      Completer<List<TripPlan>>().future;

  @override
  Future<void> deleteTrip(String id) => Completer<void>().future;
}

/// A cloud in memory that merges saves like the real transaction does.
class _MemoryCloud extends Fake implements TripCloudRepository {
  final trips = <String, TripPlan>{};

  @override
  Future<List<TripPlan>> getTripsFor(String uid) async => [
    for (final t in trips.values)
      if (t.memberUids.contains(uid)) t,
  ];

  @override
  Future<TripPlan> saveMerged(
    TripPlan plan, {
    TripPlan? base,
    bool savedByOwner = false,
  }) async {
    final remote = trips[plan.id];
    final stored =
        (remote == null || base == null
                ? plan
                : mergePlans(
                    base: base,
                    local: plan,
                    remote: remote,
                    savedByOwner: savedByOwner,
                  ))
            .copyWith(cloudSynced: true);
    trips[plan.id] = stored;
    return stored;
  }
}

TripStop _stop(String id, {bool done = false}) => TripStop(
  id: id,
  placeName: id,
  description: '',
  timeSlot: 'Morning',
  durationMinutes: 60,
  latitude: 25.3,
  longitude: 83.0,
  category: 'heritage',
  isCompleted: done,
);

/// Phone storage in memory.
class _MemoryTrips extends Fake implements SavedTripsRepository {
  final trips = <String, TripPlan>{};

  @override
  Future<List<TripPlan>> getAllTrips() async => trips.values.toList();

  @override
  Future<TripPlan?> getTrip(String id) async => trips[id];

  @override
  Future<void> saveTrip(TripPlan trip) async => trips[trip.id] = trip;

  @override
  Future<void> deleteTrip(String id) async => trips.remove(id);
}

TripPlan _trip(String id) => TripPlan(
  id: id,
  title: 'Varanasi',
  destination: 'Varanasi',
  daysCount: 2,
  createdAt: DateTime(2026, 10, 17),
  days: const [],
);

void main() {
  late _SilentCloud cloud;
  late _MemoryTrips local;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _SilentCloud();
    local = _MemoryTrips();
    container = ProviderContainer(
      overrides: [
        tripSyncUidProvider.overrideWithValue('me'), // Signed in.
        tripCloudRepositoryProvider.overrideWithValue(cloud),
        savedTripsRepositoryProvider.overrideWithValue(local),
      ],
    );
    addTearDown(container.dispose);
  });

  test('save returns at once and keeps the trip on the phone', () async {
    final notifier = container.read(savedTripsListProvider.notifier);
    final stored = await notifier
        .save(_trip('t1'))
        .timeout(const Duration(seconds: 2));

    expect(stored.ownerUid, 'me');
    expect(stored.cloudSynced, isFalse); // Not confirmed by the cloud.
    expect(local.trips, contains('t1'));
    // The upload starts in the background, once the last cloud copy (for
    // merging) has been read.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cloud.saves, 1);
  });

  testWidgets('the list loads from the phone when the cloud is silent', (
    tester,
  ) async {
    local.trips['t1'] = _trip('t1');
    List<TripPlan>? loaded;
    unawaited(
      container.read(savedTripsListProvider.future).then((t) => loaded = t),
    );
    // Widget tests run on a fake clock: jump past the cloud time limit.
    await tester.pump(SavedTripsNotifier.cloudTimeout);
    await tester.pump(const Duration(seconds: 1));
    expect(loaded?.map((t) => t.id), ['t1']);
  });

  test('delete returns at once and remembers to delete in the cloud', () async {
    local.trips['t1'] = _trip('t1')
        .copyWith(ownerUid: 'me', memberUids: ['me'], cloudSynced: true);
    await container
        .read(savedTripsListProvider.notifier)
        .delete('t1')
        .timeout(const Duration(seconds: 2));

    expect(local.trips, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('trip_plans_pending_deletes_v1'), ['delete:t1']);
  });

  test(
    'a friend edits the shared trip meanwhile: both edits survive',
    () async {
      final cloud = _MemoryCloud();
      final local = _MemoryTrips();
      final shared = TripPlan(
        id: 'trip',
        title: 'Varanasi',
        destination: 'Varanasi',
        daysCount: 1,
        createdAt: DateTime(2026, 11, 1),
        days: [
          TripDayPlan(
            dayNumber: 1,
            title: 'Ghats',
            stops: [_stop('a'), _stop('b')],
          ),
        ],
        ownerUid: 'friend',
        memberUids: const ['friend', 'me'],
        updatedAt: DateTime(2026, 11, 1),
        cloudSynced: true,
      );
      cloud.trips['trip'] = shared;
      final container = ProviderContainer(
        overrides: [
          tripSyncUidProvider.overrideWithValue('me'),
          tripCloudRepositoryProvider.overrideWithValue(cloud),
          savedTripsRepositoryProvider.overrideWithValue(local),
        ],
      );
      addTearDown(container.dispose);

      // First sync: this phone gets the trip (and remembers the cloud copy).
      await container.read(savedTripsListProvider.future);

      // The friend adds a stop on their phone.
      final day = cloud.trips['trip']!.days.single;
      cloud.trips['trip'] = cloud.trips['trip']!.copyWith(
        days: [
          day.copyWith(stops: [...day.stops, _stop('theirs')]),
        ],
        updatedAt: DateTime(2026, 11, 2),
      );

      // Meanwhile I mark a done, from the copy I had.
      final mine = (await local.getTrip('trip'))!;
      await container
          .read(savedTripsListProvider.notifier)
          .save(
            mine.copyWith(
              days: [
                mine.days.single.copyWith(
                  stops: [_stop('a', done: true), _stop('b')],
                ),
              ],
              updatedAt: DateTime(2026, 11, 3),
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      for (final copy in [
        cloud.trips['trip']!,
        (await local.getTrip('trip'))!,
      ]) {
        final stops = copy.days.single.stops;
        expect(stops.map((s) => s.id), ['a', 'b', 'theirs']);
        expect(stops.first.isCompleted, isTrue);
      }
      expect(cloud.trips['trip']!.memberUids, ['friend', 'me']);
    },
  );
}
