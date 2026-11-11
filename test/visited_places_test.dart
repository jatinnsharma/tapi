import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/checkpoint.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AdventureSession _trip(String id, AdventureStatus status) => AdventureSession(
  id: id,
  title: id,
  startedAt: DateTime(2026, 10, 16, 9),
  status: status,
);

Checkpoint _arrival(String placeId, String tripId, {bool reached = true}) =>
    Checkpoint(
      id: 'dest-$placeId@$tripId',
      adventureId: tripId,
      name: placeId,
      latitude: 30.75,
      longitude: 76.8,
      reachedAt: reached ? DateTime(2026, 10, 16, 10) : null,
    );

void main() {
  test('reads the place id out of a destination checkpoint id', () {
    expect(
      AdventureRepository.placeIdFromCheckpointId('dest-loc-rock-garden@t1'),
      'loc-rock-garden',
    );
    expect(AdventureRepository.placeIdFromCheckpointId('dest-p1'), 'p1');
    expect(AdventureRepository.placeIdFromCheckpointId('stop-3@t1'), isNull);
    expect(AdventureRepository.placeIdFromCheckpointId('dest-@t1'), isNull);
  });

  test('visited places: reached on a counted or running trip only', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_visited');
    await databaseFactoryFfi.setDatabasesPath(dir.path);

    final repo = AdventureRepository(DatabaseService());
    Future<void> add(AdventureSession trip, List<Checkpoint> stops) async {
      await repo.createAdventure(trip);
      await repo.insertCheckpoints(stops);
    }

    await add(_trip('done', AdventureStatus.completed), [
      _arrival('lake', 'done'),
    ]);
    await add(_trip('now', AdventureStatus.active), [
      _arrival('garden', 'now'),
    ]);
    await add(_trip('failed', AdventureStatus.unverified), [
      _arrival('fort', 'failed'),
    ]);
    await add(_trip('notyet', AdventureStatus.completed), [
      _arrival('market', 'notyet', reached: false),
    ]);
    // A second visit to the same place still gives one id.
    await add(_trip('again', AdventureStatus.completed), [
      _arrival('lake', 'again'),
    ]);

    expect(await repo.getVisitedPlaceIds(), {'lake', 'garden'});
  });
}
