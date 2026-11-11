import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/domain/checkpoint.dart';
import 'package:real_world_exploration/features/tracking/domain/directions.dart';
import 'package:real_world_exploration/features/tracking/presentation/start_adventure_view.dart';
import 'package:real_world_exploration/features/weather/application/weather_service.dart';

class _RecordingTracking extends TrackingService {
  final started = <(String, Destination?)>[];

  @override
  Future<void> startAdventure({
    required String title,
    List<Checkpoint> checkpoints = const [],
    String? groupAdventureId,
    Destination? destination,
  }) async {
    started.add((title, destination));
  }
}

void main() {
  late _RecordingTracking tracking;

  Future<void> pump(WidgetTester tester, Widget view) async {
    tracking = _RecordingTracking();
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingServiceProvider.overrideWith(() => tracking),
          currentWeatherProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          // Reduced motion: no pulsing, so the screen can settle.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: view,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('start uses the name typed in', (tester) async {
    await pump(tester, const StartAdventureView(title: 'New Adventure'));
    await tester.enterText(
      find.byKey(const ValueKey('adventure-name')),
      '  Morning walk  ',
    );
    await tester.tap(find.byKey(const ValueKey('start-button')));
    await tester.pump();
    expect(tracking.started.single.$1, 'Morning walk');
  });

  testWidgets('an empty name falls back to the default', (tester) async {
    await pump(tester, const StartAdventureView(title: 'New Adventure'));
    await tester.enterText(find.byKey(const ValueKey('adventure-name')), '');
    await tester.tap(find.byKey(const ValueKey('start-button')));
    await tester.pump();
    expect(tracking.started.single.$1, 'New Adventure');
  });

  testWidgets('a double tap starts only once', (tester) async {
    await pump(tester, const StartAdventureView(title: 'New Adventure'));
    await tester.tap(find.byKey(const ValueKey('start-button')));
    await tester.tap(find.byKey(const ValueKey('start-button')));
    await tester.pump();
    expect(tracking.started, hasLength(1));
  });

  testWidgets('a trip to a place explains journey, trek and proof', (
    tester,
  ) async {
    const place = Destination(
      id: 'p',
      name: 'Sukhna Lake',
      latitude: 30.74,
      longitude: 76.81,
      xpReward: 60,
    );
    await pump(
      tester,
      const StartAdventureView(title: 'Sukhna Lake', destination: place),
    );
    expect(find.text('Heading to Sukhna Lake · +60 XP'), findsOneWidget);
    expect(find.text('1. Journey'), findsOneWidget);
    expect(find.text('2. Trek'), findsOneWidget);
    expect(find.text('3. Proof photo'), findsOneWidget);
    expect(find.text('4. Finish'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start-button')));
    await tester.pump();
    expect(tracking.started.single.$2, place);
  });

  testWidgets('a free trip starts its trek at once', (tester) async {
    await pump(tester, const StartAdventureView(title: 'New Adventure'));
    expect(find.text('1. Journey'), findsNothing);
    expect(find.text('1. Trek'), findsOneWidget);
    expect(find.textContaining('Starts right away'), findsOneWidget);
  });
}
