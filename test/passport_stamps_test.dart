import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/explore/domain/city.dart';
import 'package:real_world_exploration/features/passport/application/passport_service.dart';
import 'package:real_world_exploration/features/passport/domain/passport_stamp.dart';
import 'package:real_world_exploration/features/passport/presentation/passport_book_screen.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/domain/checkpoint.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

City _city(String id, String name, double lat, double lng, String category) =>
    City(
      id: id,
      name: name,
      state: 'State of $name',
      latitude: lat,
      longitude: lng,
      blurb: '',
      imageUrl: '',
      category: category,
    );

final _varanasi = _city('varanasi', 'Varanasi', 25.3176, 82.9739, 'spiritual');
final _jaipur = _city('jaipur', 'Jaipur', 26.9124, 75.7873, 'heritage');

PlaceVisit _visit(String name, double lat, double lng, DateTime at) =>
    PlaceVisit(
      placeId: name,
      name: name,
      latitude: lat,
      longitude: lng,
      reachedAt: at,
      adventureId: 'trip-$name',
    );

void main() {
  group('buildStamps', () {
    test('one stamp per city, numbered in the order earned', () {
      final stamps = buildStamps(
        [
          _visit('Hawa Mahal', 26.9239, 75.8267, DateTime(2026, 3, 2)),
          _visit('Assi Ghat', 25.2900, 83.0060, DateTime(2026, 1, 10)),
          _visit('Sarnath', 25.3810, 83.0214, DateTime(2026, 1, 11)),
          _visit('Assi Ghat', 25.2900, 83.0060, DateTime(2026, 2, 1)),
        ],
        [_jaipur, _varanasi],
      );
      expect(stamps.map((s) => s.city.name), ['Varanasi', 'Jaipur']);
      expect(stamps.first.serialLabel, 'No. 001');
      expect(stamps.first.earnedAt, DateTime(2026, 1, 10));
      // A place reached twice is listed once.
      expect(stamps.first.placeNames, ['Assi Ghat', 'Sarnath']);
      expect(stamps.last.serial, 2);
    });

    test('a visit far from every catalog city earns nothing', () {
      final stamps = buildStamps(
        [_visit('Middle of nowhere', 22.0, 79.0, DateTime(2026, 1, 1))],
        [_jaipur, _varanasi],
      );
      expect(stamps, isEmpty);
      expect(buildStamps(const [], [_jaipur]), isEmpty);
      expect(
        buildStamps([_visit('x', 25.3, 83.0, DateTime(2026))], const []),
        isEmpty,
      );
    });
  });

  test('only places reached on counted trips are stamped', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('rwe_passport');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    final repo = AdventureRepository(DatabaseService());

    Future<void> trip(
      String id,
      AdventureStatus status, {
      bool reached = true,
    }) => repo.createAdventureWithCheckpoints(
      AdventureSession(
        id: id,
        title: id,
        startedAt: DateTime(2026, 1, 1),
        status: status,
      ),
      [
        Checkpoint(
          id: 'dest-place-$id@$id',
          adventureId: id,
          name: 'Place $id',
          latitude: 25.31,
          longitude: 82.97,
          reachedAt: reached ? DateTime(2026, 1, 1, 10) : null,
        ),
      ],
    );

    await trip('done', AdventureStatus.completed);
    await trip('running', AdventureStatus.active);
    await trip('failed', AdventureStatus.unverified);
    await trip('thrown', AdventureStatus.discarded);
    await trip('missed', AdventureStatus.completed, reached: false);

    final visits = await repo.getCountedPlaceVisits();
    expect(visits.map((v) => v.placeId), ['place-done']);
    expect(visits.single.name, 'Place done');
    expect(visits.single.reachedAt, DateTime(2026, 1, 1, 10));
  });

  testWidgets('passport book: empty, then stamps', (tester) async {
    Future<void> pump(List<PassportStamp> stamps) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            passportStampsProvider.overrideWith((ref) async => stamps),
          ],
          child: const MaterialApp(home: PassportBookScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(const []);
    expect(find.text('No stamps yet'), findsOneWidget);

    await pump([
      PassportStamp(
        city: _varanasi,
        serial: 1,
        earnedAt: DateTime(2026, 1, 10),
        placeNames: const ['Assi Ghat'],
      ),
    ]);
    expect(find.text('1 city stamped'), findsOneWidget);
    expect(find.text('VARANASI'), findsOneWidget);

    await tester.tap(find.text('VARANASI'));
    await tester.pumpAndSettle();
    expect(find.text('Varanasi, State of Varanasi'), findsOneWidget);
    expect(find.text('Assi Ghat'), findsOneWidget);
    expect(find.text('Share stamp'), findsOneWidget);
  });
}
