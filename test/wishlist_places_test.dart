import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ExploreLocation _place(String id, LocationCategory category) => ExploreLocation(
  id: id,
  name: id,
  category: category,
  description: '',
  latitude: 25.31,
  longitude: 83.01,
);

void main() {
  test('saved places are found by id, whatever their kind', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_wishlist');
    await databaseFactoryFfi.setDatabasesPath(dir.path);

    final repo = LocationRepository(DatabaseService());
    // A food stop from a trip plan: kept out of the map and Home lists.
    final food = _place('plan-stop-kachori', LocationCategory.food);
    final ghat = _place('wiki-ghat', LocationCategory.heritage);
    await repo.insertMany([food, ghat]);

    expect((await repo.getAll()).map((p) => p.id), isNot(contains(food.id)));
    final found = await repo.getByIds({food.id, ghat.id, 'missing'});
    expect(found.map((p) => p.id).toSet(), {food.id, ghat.id});
    expect(await repo.getByIds({}), isEmpty);
  });

  test('saving again does not overwrite a stored place', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_wishlist2');
    await databaseFactoryFfi.setDatabasesPath(dir.path);

    final repo = LocationRepository(DatabaseService());
    final stored = _place(
      'wiki-ghat',
      LocationCategory.heritage,
    ).copyWith(discoveredAt: DateTime(2026, 11, 1));
    await repo.insertMany([stored]);
    // The same place opened from a search result, without its history.
    await repo.insertMany([_place('wiki-ghat', LocationCategory.heritage)]);

    final found = await repo.getByIds({'wiki-ghat'});
    expect(found.single.discoveredAt, DateTime(2026, 11, 1));
  });

  test('adding places tells listeners (the Map reloads)', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_changes');
    await databaseFactoryFfi.setDatabasesPath(dir.path);

    final repo = LocationRepository(DatabaseService());
    var events = 0;
    final sub = repo.changes.listen((_) => events++);
    await repo.insertMany([_place('wiki-fort', LocationCategory.heritage)]);
    await repo.insertMany(const []);
    await Future<void>.delayed(Duration.zero);
    expect(events, 1);
    await sub.cancel();
    repo.dispose();
  });
}
