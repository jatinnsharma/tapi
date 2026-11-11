// Saving a trip must never wait on the cloud. Firestore only confirms a
// write once its server has it, which never happens offline or before the
// Firestore database exists; the planner used to spin forever on that.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/planner/data/saved_trips_repository.dart';
import 'package:real_world_exploration/features/planner/data/trip_cloud_repository.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cloud that never answers.
class _SilentCloud extends Fake implements TripCloudRepository {
  int saves = 0;

  @override
  Future<void> saveTrip(TripPlan plan) {
    saves++;
    return Completer<void>().future;
  }

  @override
  Future<List<TripPlan>> getTripsFor(String uid) =>
      Completer<List<TripPlan>>().future;

  @override
  Future<void> deleteTrip(String id) => Completer<void>().future;
}

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
    expect(cloud.saves, 1); // The upload was started in the background.
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
}
