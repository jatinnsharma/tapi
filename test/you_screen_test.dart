import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/auth/application/display_name_provider.dart';
import 'package:real_world_exploration/features/challenges/application/streak_service.dart';
import 'package:real_world_exploration/features/challenges/domain/streak_data.dart';
import 'package:real_world_exploration/features/locations/data/location_repository.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/passport/application/passport_service.dart';
import 'package:real_world_exploration/features/profile/application/achievement_service.dart';
import 'package:real_world_exploration/features/profile/application/rank_style_service.dart';
import 'package:real_world_exploration/features/profile/application/user_profile_service.dart';
import 'package:real_world_exploration/features/profile/domain/explorer_level.dart';
import 'package:real_world_exploration/features/profile/domain/rank_style.dart';
import 'package:real_world_exploration/features/profile/profile_screen.dart';
import 'package:real_world_exploration/features/profile/regions_screen.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';

class _Cities extends Fake implements LocationRepository {
  _Cities(this.cities);
  final List<RegionProgress> cities;

  @override
  Future<List<RegionProgress>> getCityCompletion() async => cities;
}

Future<void> _pumpYou(
  WidgetTester tester, {
  int xp = 1240,
  List<RegionProgress> cities = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) async => UserStats(
            totalXp: xp,
            completedAdventureCount: 7,
            totalDistanceKm: 12.4,
            recentAdventures: const [],
          ),
        ),
        displayNameProvider.overrideWith((ref) => 'Asha'),
        rankStyleProvider.overrideWith(
          (ref) async => StyleState(totalXp: xp, equipped: highestUnlocked(xp)),
        ),
        streakDataProvider.overrideWith(
          (ref) async => const StreakData(
            currentStreak: 0,
            bestStreak: 0,
            completedToday: false,
            freezesAvailable: 0,
          ),
        ),
        achievementsProvider.overrideWith((ref) async => const []),
        passportStampsProvider.overrideWith((ref) async => const []),
        visitedPlaceIdsProvider.overrideWith((ref) async => {'a', 'b', 'c'}),
        locationRepositoryProvider.overrideWithValue(_Cities(cities)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  group('rank progress', () {
    test('measures the way to the next rank, not every 100 XP', () {
      final r = ExplorerLevel.rankProgress(1750);
      expect(r.current.title, 'Explorer');
      expect(r.next!.title, 'Adventurer');
      expect(r.xpToNext, 750);
      expect(r.progress, closeTo(0.5, 0.001));
    });

    test('is full at the top rank', () {
      final r = ExplorerLevel.rankProgress(80000);
      expect(r.next, isNull);
      expect(r.progress, 1);
    });
  });

  test('trip dates are relative for a week, then a date', () {
    final now = DateTime(2026, 11, 18, 10);
    expect(tripDateLabel(DateTime(2026, 11, 18, 7), now), 'Today');
    expect(tripDateLabel(DateTime(2026, 11, 17, 23), now), 'Yesterday');
    expect(tripDateLabel(DateTime(2026, 11, 14), now), '4 days ago');
    expect(tripDateLabel(DateTime(2026, 7, 2), now), '2 Jul');
    expect(tripDateLabel(DateTime(2025, 7, 2), now), '2 Jul 2025');
  });

  test('regions not started are hidden unless asked for', () {
    const groups = [
      (
        title: 'Cities',
        regions: [
          RegionProgress(name: 'Pune', discovered: 0, total: 40),
          RegionProgress(name: 'Jaipur', discovered: 2, total: 10),
          RegionProgress(name: 'Agra', discovered: 1, total: 2),
        ],
      ),
      (
        title: 'States',
        regions: [RegionProgress(name: 'Kerala', discovered: 0, total: 9)],
      ),
    ];
    final shown = visibleRegionGroups(groups, showAll: false);
    expect(shown.map((g) => g.title), ['Cities']);
    expect(shown.single.regions.map((r) => r.name), ['Agra', 'Jaipur']);
    expect(visibleRegionGroups(groups, showAll: true).length, 2);
  });

  testWidgets('one rank meter; XP shown once', (tester) async {
    await _pumpYou(tester);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Explorer · Level 5'), findsOneWidget);
    expect(find.text('1,240 XP'), findsOneWidget);
    expect(find.text('1,260 XP to Adventurer'), findsOneWidget);
    expect(find.text('Total XP'), findsNothing);
    // Three lifetime stats and three collections.
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Places visited'), findsOneWidget);
    expect(find.text('Stars'), findsOneWidget);
    expect(find.text('City stamps'), findsOneWidget);
    expect(find.text('Routes & poster'), findsOneWidget);
  });

  testWidgets('a new explorer gets an invitation, not a wall of 0% bars', (
    tester,
  ) async {
    await _pumpYou(tester);
    await tester.scrollUntilVisible(
      find.text('Places you discover fill in your map here.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('All regions', skipOffstage: false), findsNothing);
  });

  testWidgets('with progress, only the top city shows, plus All regions', (
    tester,
  ) async {
    await _pumpYou(
      tester,
      cities: const [
        RegionProgress(name: 'Jaipur', discovered: 2, total: 10),
        RegionProgress(name: 'Agra', discovered: 5, total: 20),
        RegionProgress(name: 'Pune', discovered: 0, total: 40),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('All regions'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Agra'), findsOneWidget);
    expect(find.text('Jaipur'), findsNothing);
    expect(find.text('Pune'), findsNothing);
  });

  testWidgets('meets tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpYou(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('fits a 320 dp phone at 1.3x text without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpYou(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
