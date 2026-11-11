// A whole trip through the real tracking service, fed by a pretend GPS:
// journey and trek are split, saved, and judged on the trek only.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/core/services/gps_fix.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/directions.dart';
import 'package:real_world_exploration/features/tracking/domain/trip_split.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _mPerDegLat = 111200.0;
const _home = LatLng(30.7333, 76.7794);
LatLng _north(LatLng from, double m) =>
    LatLng(from.latitude + m / _mPerDegLat, from.longitude);

class _FakeGps extends LocationService {
  final controller = StreamController<GpsFix>.broadcast();
  @override
  Stream<GpsFix> getAdventureTrackingStream({bool batterySaving = false}) =>
      controller.stream;
}

/// Drives a trip: emits readings and waits for each to be processed.
class _Driver {
  _Driver(this.container, this.gps);
  final ProviderContainer container;
  final _FakeGps gps;
  LatLng at = _home;
  DateTime t = DateTime.now().subtract(const Duration(hours: 3));

  int get _points => container.read(trackingServiceProvider).routePoints.length;

  Future<void> _emit() async {
    final before = _points;
    gps.controller.add(GpsFix(position: at, time: t, accuracyMeters: 8));
    for (var i = 0; i < 1000 && _points == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> start() => _emit();

  Future<void> move(double meters, double speed) async {
    const every = 10;
    final step = speed * every;
    for (var done = 0.0; done < meters - 0.01; done += step) {
      final d = (meters - done) < step ? meters - done : step;
      at = _north(at, d);
      t = t.add(Duration(milliseconds: (d / speed * 1000).round()));
      await _emit();
    }
  }
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('rwe_split');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  Future<(ProviderContainer, _Driver)> startTrip(Destination dest) async {
    final gps = _FakeGps();
    final c = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(gps)],
    );
    addTearDown(c.dispose);
    await c
        .read(trackingServiceProvider.notifier)
        .startAdventure(
          title: dest.name,
          checkpoints: [dest.toCheckpoint()],
          destination: dest,
        );
    final driver = _Driver(c, gps);
    await driver.start();
    return (c, driver);
  }

  test('drive to a place, walk around it: journey and trek apart', () async {
    final place = Destination(
      id: 'wiki-77',
      name: 'Sukhna Lake',
      latitude: _north(_home, 3000).latitude,
      longitude: _home.longitude,
    );
    final (c, drive) = await startTrip(place);

    var state = c.read(trackingServiceProvider);
    expect(state.phase, TripPhase.toTrekStart);
    expect(state.metersToTrekStart, closeTo(3000, 10));

    await drive.move(2900, 15); // by car to the car park
    state = c.read(trackingServiceProvider);
    expect(state.phase, TripPhase.trekking);
    expect(state.metersToTrekStart, isNull);

    await drive.move(500, 1.4); // on foot around the lake

    final done = await c
        .read(trackingServiceProvider.notifier)
        .finishAdventure();
    expect(done, isNotNull);
    expect(done!.status, AdventureStatus.completed);
    expect(done.journeyMeters, closeTo(2900, 20));
    expect(done.trekMeters, closeTo(500, 20));
    expect(done.trekSeconds, closeTo(500 / 1.4, 20));
    expect(done.distanceMeters, closeTo(3400, 30)); // everything together
    expect(done.xpEarned, greaterThanOrEqualTo(100)); // completion bonus

    // Saved, and read back the same.
    final saved =
        (await c
                .read(adventureRepositoryProvider)
                .getRecentAdventures(limit: 50))
            .firstWhere((a) => a.id == done.id);
    expect(saved.trekMeters, closeTo(done.trekMeters, 0.01));
    expect(saved.journeyMeters, closeTo(done.journeyMeters, 0.01));
  });

  test('a long drive with no trek is not counted and pays no bonus', () async {
    final place = Destination(
      id: 'wiki-78',
      name: 'Rock Garden',
      latitude: _north(_home, 6000).latitude,
      longitude: _home.longitude,
    );
    final (c, drive) = await startTrip(place);
    await drive.move(6000, 15); // drive there, never get out

    final done = await c
        .read(trackingServiceProvider.notifier)
        .finishAdventure();
    expect(done!.status, AdventureStatus.unverified);
    expect(done.trekMeters, lessThan(200));
    expect(done.journeyMeters, greaterThan(5500));
    expect(done.xpEarned, 0);
    expect(
      c.read(trackingServiceProvider).xpNotice,
      contains("journey there doesn't count"),
    );
  });

  test('the database upgrade keeps old trips as all trek', () async {
    final dir = Directory.systemTemp.createTempSync('rwe_upgrade');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    addTearDown(() => databaseFactoryFfi.setDatabasesPath(tmp.path));

    // A version 5 database with one old trip.
    final path = p.join(dir.path, 'real_world_exploration.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE adventures (
              id TEXT PRIMARY KEY, title TEXT NOT NULL,
              started_at TEXT NOT NULL, ended_at TEXT, status TEXT NOT NULL,
              distance_meters REAL NOT NULL DEFAULT 0,
              duration_seconds INTEGER NOT NULL DEFAULT 0,
              xp_earned INTEGER NOT NULL DEFAULT 0,
              group_adventure_id TEXT)''');
          await db.execute('CREATE TABLE memories (id TEXT PRIMARY KEY)');
          await db.insert('adventures', {
            'id': 'old-1',
            'title': 'Old walk',
            'started_at': '2026-01-01T08:00:00.000',
            'status': 'completed',
            'distance_meters': 2500.0,
            'duration_seconds': 1800,
            'xp_earned': 150,
          });
        },
      ),
    );
    await old.close();

    final repo = AdventureRepository(DatabaseService());
    final trips = await repo.getRecentAdventures(limit: 5);
    final trip = trips.single;
    expect(trip.trekMeters, 2500);
    expect(trip.trekSeconds, 1800);
    expect(trip.journeyMeters, 0);
    expect(trip.journeySeconds, 0);
  });
}
