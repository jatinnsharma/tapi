import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/database/database_service.dart';
import 'package:real_world_exploration/features/journal/domain/calendar_month.dart';
import 'package:real_world_exploration/features/journal/presentation/calendar_screen.dart';
import 'package:real_world_exploration/features/memories/data/memory_repository.dart';
import 'package:real_world_exploration/features/memories/domain/memory_model.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _today = DateTime(2026, 10, 16, 10);

AdventureSession _trip(String title, DateTime at, {AdventureStatus? status}) =>
    AdventureSession(
      id: title.toLowerCase().replaceAll(' ', '-'),
      title: title,
      startedAt: at,
      endedAt: at.add(const Duration(hours: 2)),
      status: status ?? AdventureStatus.completed,
      durationSeconds: 7200,
      journeyMeters: 2900,
      journeySeconds: 700,
      trekMeters: 1240,
      trekSeconds: 1500,
      xpEarned: 160,
    );

Memory _voice(String id, DateTime at) => Memory(
  id: id,
  type: MemoryType.voiceNote,
  filePath: '/x/$id.m4a',
  timestamp: at,
);

void main() {
  final october = groupByDay(
    [
      _trip('Sukhna Lake', DateTime(2026, 10, 15, 7, 5)),
      _trip('Rock Garden', DateTime(2026, 10, 3, 16)),
    ],
    [_voice('note', DateTime(2026, 10, 15, 8))],
  );

  Future<List<DateTime>> pump(WidgetTester tester) async {
    final asked = <DateTime>[];
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarMonthProvider.overrideWith((ref, month) async {
            asked.add(month);
            return month == DateTime(2026, 10) ? october : {};
          }),
        ],
        child: MaterialApp(home: CalendarScreen(today: _today)),
      ),
    );
    await tester.pumpAndSettle();
    return asked;
  }

  testWidgets('shows the month and its totals', (tester) async {
    await pump(tester);
    expect(find.text('October'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    final summary = find.byKey(const ValueKey('month-summary'));
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: summary, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .toList();
    // 2 trips, 2.48 km trekked, 1 memory, 2 active days.
    expect(texts, [
      '2',
      'Trips',
      '2.48 km',
      'Trekked',
      '1',
      'Memories',
      '2',
      'Active days',
    ]);
  });

  testWidgets('a day with a trip opens its details', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('day-15')));
    await tester.pumpAndSettle();

    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('15 October 2026'), findsOneWidget);
    expect(find.text('1 trip'), findsOneWidget);
    expect(find.text('Sukhna Lake'), findsOneWidget);
    expect(find.text('07:05 – 09:05'), findsOneWidget);
    expect(find.text('2.90 km'), findsOneWidget); // journey
    expect(find.text('1.24 km'), findsOneWidget); // trek
    expect(find.text('+160 XP'), findsOneWidget);
    expect(find.text('Trip details'), findsOneWidget);
    expect(find.text('1 memory'), findsOneWidget);
  });

  testWidgets('an empty day says so', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('day-10')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing on this day'), findsOneWidget);
  });

  testWidgets('future days and months are not open', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('day-20')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Tuesday'), findsNothing);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October'), findsOneWidget);
  });

  testWidgets('earlier months, and back to today', (tester) async {
    final asked = await pump(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
    expect(asked, contains(DateTime(2026, 9)));

    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pumpAndSettle();
    expect(find.text('October'), findsOneWidget);
  });

  testWidgets('swiping changes the month', (tester) async {
    await pump(tester);
    await tester.fling(find.text('October'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
  });

  group('Loading a month from the database', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactoryFfi.setDatabasesPath(
        Directory.systemTemp.createTempSync('rwe_cal').path,
      );
    });

    test('only that month, local or UTC times, no discarded trips', () async {
      final db = DatabaseService();
      final trips = AdventureRepository(db);
      final memories = MemoryRepository(db);
      await trips.createAdventure(
        _trip('In October', DateTime(2026, 10, 1, 0, 30)),
      );
      await trips.createAdventure(
        _trip('Last day', DateTime(2026, 10, 31, 23, 30)),
      );
      await trips.createAdventure(
        _trip('In September', DateTime(2026, 9, 30, 23)),
      );
      await trips.createAdventure(
        _trip('In November', DateTime(2026, 11, 1, 0, 10)),
      );
      await trips.createAdventure(
        _trip(
          'Thrown away',
          DateTime(2026, 10, 5),
          status: AdventureStatus.discarded,
        ),
      );
      await memories.saveMemory(
        _voice('utc', DateTime(2026, 10, 12, 9).toUtc()),
      );
      await memories.saveMemory(_voice('local', DateTime(2026, 10, 13, 9)));

      final container = ProviderContainer(
        overrides: [databaseServiceProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final month = await container.read(
        calendarMonthProvider(DateTime(2026, 10)).future,
      );

      final titles = month.values.expand((d) => d.trips).map((t) => t.title);
      expect(titles, unorderedEquals(['In October', 'Last day']));
      expect(month[DateTime(2026, 10, 12)]!.memories.single.id, 'utc');
      expect(month[DateTime(2026, 10, 13)]!.memories.single.id, 'local');
    });
  });
}
