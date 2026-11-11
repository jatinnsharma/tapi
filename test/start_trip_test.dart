import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/services/gps_fix.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/checkpoint.dart';
import 'package:real_world_exploration/features/tracking/domain/directions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoGps extends LocationService {
  @override
  Stream<GpsFix> getAdventureTrackingStream({bool batterySaving = false}) =>
      const Stream.empty();
}

const _rockGarden = Destination(
  id: 'wiki-1',
  name: 'Rock Garden',
  latitude: 30.7525,
  longitude: 76.8101,
);

ProviderContainer _app() {
  final c = ProviderContainer(
    overrides: [locationServiceProvider.overrideWithValue(_NoGps())],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _start(ProviderContainer c) => c
    .read(trackingServiceProvider.notifier)
    .startAdventure(
      title: 'Rock Garden',
      checkpoints: [_rockGarden.toCheckpoint()],
      destination: _rockGarden,
    )
    .timeout(const Duration(seconds: 10));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_db');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({});
  });

  test('starting a trip to a place creates the session', () async {
    final c = _app();
    await _start(c);
    final state = c.read(trackingServiceProvider);
    expect(state.hasSession, true);
    expect(state.checkpoints, hasLength(1));
    expect(
      state.checkpoints.single.id,
      startsWith(Destination.checkpointIdPrefix),
    );
  });

  test('a second trip to the same place starts too', () async {
    // Each ProviderContainer is a fresh app run on the same phone database.
    await _start(_app());
    final again = _app();
    await _start(again);
    expect(again.read(trackingServiceProvider).hasSession, true);
    // And a third, for good measure.
    final third = _app();
    await _start(third);
    expect(third.read(trackingServiceProvider).hasSession, true);
  });

  test('a trip that can\'t be saved leaves nothing behind', () async {
    final c = _app();
    final repo = c.read(adventureRepositoryProvider);
    final session = AdventureSession(
      id: 'half-made',
      title: 'x',
      startedAt: DateTime.now(),
      status: AdventureStatus.active,
    );
    final checkpoint = Checkpoint(
      id: 'dest-wiki-1',
      adventureId: 'half-made',
      name: 'Rock Garden',
      latitude: 30.7525,
      longitude: 76.8101,
    );
    // Two checkpoints with the same id: the second insert must fail.
    await expectLater(
      repo.createAdventureWithCheckpoints(session, [checkpoint, checkpoint]),
      throwsA(anything),
    );
    final all = await repo.getRecentAdventures(limit: 100);
    expect(all.where((a) => a.id == 'half-made'), isEmpty);
  });

  test('empty abandoned trips are cleaned up, real ones are not', () async {
    final c = _app();
    final repo = c.read(adventureRepositoryProvider);
    final old = DateTime.now().subtract(const Duration(hours: 2));
    AdventureSession trip(String id, {double meters = 0, DateTime? at}) =>
        AdventureSession(
          id: id,
          title: 't',
          startedAt: at ?? old,
          status: AdventureStatus.active,
          distanceMeters: meters,
        );
    await repo.createAdventure(trip('empty-old'));
    await repo.createAdventure(trip('walked-old', meters: 500));
    await repo.createAdventure(trip('empty-new', at: DateTime.now()));

    expect(await repo.removeEmptyAbandonedTrips(), greaterThanOrEqualTo(1));
    final ids = (await repo.getRecentAdventures(limit: 100)).map((a) => a.id);
    expect(ids, isNot(contains('empty-old')));
    expect(ids, contains('walked-old'));
    expect(ids, contains('empty-new')); // might still be starting
  });
}
