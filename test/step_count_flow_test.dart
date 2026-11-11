// Step counting through the real tracking service, with a pretend GPS and a
// pretend step sensor.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/core/services/gps_fix.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/core/services/step_service.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/directions.dart';
import 'package:real_world_exploration/features/tracking/presentation/journey_trek_breakdown.dart';
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

class _FakeSteps extends StepService {
  _FakeSteps({this.allowed = true});
  final bool allowed;
  final controller = StreamController<StepReading>.broadcast();
  var permissionAsked = 0;

  @override
  bool get supported => true;

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return allowed;
  }

  @override
  Stream<StepReading> readings() => controller.stream;
}

class _Trip {
  _Trip(this.container, this.gps, this.sensor);
  final ProviderContainer container;
  final _FakeGps gps;
  final _FakeSteps sensor;
  LatLng at = _home;
  DateTime t = DateTime.now().subtract(const Duration(hours: 3));

  /// The sensor's running total: big, as if the phone had been on for days.
  int sensorTotal = 84211;

  int get _points => container.read(trackingServiceProvider).routePoints.length;

  Future<void> _settle() =>
      Future<void>.delayed(const Duration(milliseconds: 15));

  Future<void> _fix() async {
    final before = _points;
    gps.controller.add(GpsFix(position: at, time: t, accuracyMeters: 8));
    for (var i = 0; i < 1000 && _points == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> _steps(int taken) async {
    sensorTotal += taken;
    sensor.controller.add(StepReading(sensorTotal, t));
    await _settle();
  }

  /// Moves [meters] north at [speed]; on foot, the sensor counts steps of
  /// [stride] m.
  Future<void> move(double meters, double speed, {bool onFoot = true}) async {
    const every = 10;
    final step = speed * every;
    for (var done = 0.0; done < meters - 0.01; done += step) {
      final d = (meters - done) < step ? meters - done : step;
      at = _north(at, d);
      t = t.add(Duration(milliseconds: (d / speed * 1000).round()));
      await _fix();
      await _steps(onFoot ? (d / 0.75).round() : 0);
    }
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('rwe_steps');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  Future<_Trip> start({bool allowed = true, double placeAt = 3000}) async {
    final gps = _FakeGps();
    final sensor = _FakeSteps(allowed: allowed);
    final c = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(gps),
        stepServiceProvider.overrideWithValue(sensor),
      ],
    );
    addTearDown(c.dispose);
    final place = Destination(
      id: 'wiki-${placeAt.round()}',
      name: 'Sukhna Lake',
      latitude: _north(_home, placeAt).latitude,
      longitude: _home.longitude,
    );
    await c
        .read(trackingServiceProvider.notifier)
        .startAdventure(
          title: place.name,
          checkpoints: [place.toCheckpoint()],
          destination: place,
        );
    final trip = _Trip(c, gps, sensor);
    await trip._settle();
    await trip._fix();
    await trip._steps(0); // the sensor's first reading: the starting point
    return trip;
  }

  test('counts steps, and only those on the trek as trek steps', () async {
    final trip = await start();
    await trip.move(300, 1.4); // walk to the car: journey steps
    await trip.move(2600, 15, onFoot: false); // drive
    await trip.move(600, 1.4); // the trek

    final state = trip.container.read(trackingServiceProvider);
    expect(state.stepsCounting, isTrue);
    expect(state.session!.steps, closeTo(1200, 30)); // 900 m / 0.75 m
    expect(state.session!.trekSteps, closeTo(800, 25)); // 600 m / 0.75 m

    final done = await trip.container
        .read(trackingServiceProvider.notifier)
        .finishAdventure();
    expect(done!.steps, closeTo(1200, 30));
    expect(done.trekSteps, closeTo(800, 25));
  });

  test('steps taken while paused do not count', () async {
    final trip = await start(placeAt: 100); // trek starts at once
    final service = trip.container.read(trackingServiceProvider.notifier);
    await trip.move(300, 1.4);
    final before = trip.container.read(trackingServiceProvider).session!.steps;

    await service.pauseAdventure();
    trip.sensorTotal += 5000; // walked around with the trip paused
    await service.resumeAdventure();
    await trip._settle();
    await trip._steps(0); // first reading after resuming: new starting point
    await trip.move(150, 1.4);

    final after = trip.container.read(trackingServiceProvider).session!.steps;
    expect(after - before, closeTo(200, 5)); // 150 m only
  });

  test('without permission the trip works and shows no steps', () async {
    final trip = await start(allowed: false);
    await trip.move(3000, 1.4);
    final state = trip.container.read(trackingServiceProvider);
    expect(trip.sensor.permissionAsked, 1);
    expect(state.stepsCounting, isFalse);
    expect(state.session!.steps, 0);
    expect(state.session!.trekMeters, greaterThan(150));
  });

  test('step counts read naturally', () {
    expect(formatSteps(0), '0 steps');
    expect(formatSteps(1), '1 step');
    expect(formatSteps(950), '950 steps');
    expect(formatSteps(1240), '1,240 steps');
    expect(formatSteps(1234567), '1,234,567 steps');
  });

  testWidgets('the breakdown shows steps; older trips show none', (
    tester,
  ) async {
    AdventureSession session({int steps = 0, int trekSteps = 0}) =>
        AdventureSession(
          id: 's',
          title: 't',
          startedAt: DateTime(2026, 10, 15),
          journeyMeters: 2000,
          trekMeters: 1500,
          steps: steps,
          trekSteps: trekSteps,
        );
    Future<void> show(AdventureSession s) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JourneyTrekBreakdown.ofSession(s))),
    );

    await show(session(steps: 2400, trekSteps: 2000));
    expect(find.text('2,000 steps'), findsOneWidget); // trek tile
    expect(find.text('400 steps'), findsOneWidget); // journey tile

    await show(session());
    expect(find.textContaining('steps'), findsNothing);
  });
}
