import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/locations/data/place_photos_service.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/locations/presentation/place_sheet.dart';
import 'package:real_world_exploration/features/tracking/data/adventure_repository.dart';
import 'package:real_world_exploration/features/tracking/data/directions_service.dart';
import 'package:real_world_exploration/features/wishlist/application/wishlist_service.dart';

const _lake = ExploreLocation(
  id: 'wiki-1',
  name: 'Sukhna Lake',
  description: 'A calm lake at the foot of the hills.',
  latitude: 30.742,
  longitude: 76.818,
  category: LocationCategory.lake,
  xpReward: 60,
);

const _mystery = ExploreLocation(
  id: 'mystery-1',
  name: 'Secret Garden',
  description: 'The real description gives it away.',
  latitude: 30.75,
  longitude: 76.8,
  category: LocationCategory.lake,
  mysteryHint: 'Where stones bloom.',
);

Future<void> _open(
  WidgetTester tester,
  ExploreLocation place, {
  bool undiscovered = false,
  double? distanceKm = 1.2,
}) async {
  // A small phone: the main action must still be on screen.
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        visitedPlaceIdsProvider.overrideWith((ref) async => <String>{}),
        journeyEstimateProvider.overrideWith(
          (ref, _) async => const JourneyEstimate(),
        ),
        placePhotosProvider.overrideWith((ref, _) async => const []),
        wishlistKeysProvider.overrideWith((ref) async => <String>{}),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlaceSheet(
                context,
                place: place,
                distanceKm: distanceKm,
                undiscovered: undiscovered,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Start trip is in reach without scrolling', (tester) async {
    await _open(tester, _lake);
    expect(find.text('Sukhna Lake'), findsOneWidget);
    expect(find.text('+60 XP when you get there'), findsOneWidget);
    expect(find.byTooltip('Save to wishlist'), findsOneWidget);

    final start = find.text('Start trip');
    expect(start, findsOneWidget);
    expect(tester.getRect(start).bottom, lessThanOrEqualTo(640));

    // Scroll down: how to get there comes after what the place is.
    await tester.scrollUntilVisible(
      find.text('Getting there'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.getRect(start).bottom, lessThanOrEqualTo(640));
    // The trek rules are behind the info button, not on the sheet.
    expect(find.textContaining('Trek starts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unsolved mystery keeps its name and description secret', (
    tester,
  ) async {
    await _open(tester, _mystery);
    expect(find.text('Secret Garden'), findsNothing);
    expect(find.textContaining('gives it away'), findsNothing);
    expect(find.text(ExploreLocation.mysteryName), findsOneWidget);
    expect(
      find.text('Where stones bloom.', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Start the hunt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place under the fog shows only how far it is', (tester) async {
    await _open(tester, _lake, undiscovered: true);
    expect(find.text('Sukhna Lake'), findsNothing);
    expect(find.textContaining('calm lake'), findsNothing);
    expect(find.text('Unknown place'), findsOneWidget);
    expect(find.text('1.2 km away'), findsOneWidget);
    expect(find.text('Head that way'), findsOneWidget);
    // Nothing to save until you know what it is.
    expect(find.byTooltip('Save to wishlist'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
  });

  testWidgets('meets tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _lake);
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
    await _open(tester, _lake);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
