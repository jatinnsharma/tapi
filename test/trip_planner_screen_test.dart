import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/planner/data/trip_planner_service.dart';
import 'package:real_world_exploration/features/planner/domain/planner_input.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/trip_planner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowPlanner extends Fake implements TripPlannerService {
  final calls = <PlannerInput>[];
  final completer = Completer<TripPlan>();

  @override
  Future<TripPlan> generatePlan(PlannerInput input) {
    calls.add(input);
    return completer.future;
  }
}

Future<_SlowPlanner> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final planner = _SlowPlanner();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tripPlannerServiceProvider.overrideWithValue(planner)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const TripPlannerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return planner;
}

Finder _planButton() => find.widgetWithText(FilledButton, 'Plan my trip');

void main() {
  testWidgets('Plan my trip is always visible, and needs only a destination', (
    tester,
  ) async {
    await _pump(tester);
    expect(_planButton(), findsOneWidget);
    expect(tester.widget<FilledButton>(_planButton()).onPressed, isNull);
    // The optional settings are folded away with a summary.
    expect(find.text('Tailor it'), findsOneWidget);
    expect(find.text('Budget'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Varanasi');
    await tester.pump();
    expect(tester.widget<FilledButton>(_planButton()).onPressed, isNotNull);
  });

  testWidgets('days go from 1 to 10 with a stepper', (tester) async {
    await _pump(tester);
    expect(find.text('3 days'), findsOneWidget);
    await tester.tap(find.byTooltip('More days'));
    await tester.tap(find.byTooltip('More days'));
    await tester.tap(find.byTooltip('More days'));
    await tester.pump();
    expect(find.text('6 days'), findsOneWidget);
  });

  testWidgets('planning shows progress, and Cancel saves nothing', (
    tester,
  ) async {
    final planner = await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Varanasi');
    await tester.pump();
    await tester.tap(_planButton());
    await tester.pump();

    expect(planner.calls.single.destination, 'Varanasi');
    expect(find.text('Planning Varanasi'), findsOneWidget);
    expect(find.textContaining('Finding the best places'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Where to?'), findsOneWidget);

    // The plan arriving late is dropped: still on the form, no error.
    planner.completer.completeError(StateError('late'));
    await tester.pumpAndSettle();
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Trip not planned'), findsNothing);
  });

  testWidgets('meets tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
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
    await _pump(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
