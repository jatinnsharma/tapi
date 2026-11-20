import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/core/ui/share_card.dart';
import 'package:real_world_exploration/features/planner/domain/trip_plan.dart';
import 'package:real_world_exploration/features/planner/presentation/trip_share.dart';

TripPlan _plan(int days) => TripPlan(
  id: 't1',
  title: 'Varanasi',
  destination: 'Varanasi',
  daysCount: days,
  createdAt: DateTime(2026),
  days: [
    for (var d = 1; d <= days; d++)
      TripDayPlan(dayNumber: d, title: 'Day title $d', stops: const []),
  ],
);

Future<void> _open(WidgetTester tester, TripPlan plan) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTripImageShare(context, plan),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one sheet: fixed-width preview, Share image and Copy text', (
    tester,
  ) async {
    await _open(tester, _plan(2));
    expect(find.text('Share trip'), findsOneWidget);
    expect(find.text('Share image'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    // Laid out at the export width, whatever the phone.
    final card = find.ancestor(
      of: find.byType(RepaintBoundary).last,
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(card.first).width, shareCardWidth);
  });

  testWidgets('a long trip shows three days and "+N more days"', (
    tester,
  ) async {
    await _open(tester, _plan(5));
    expect(
      find.textContaining('Day title 3', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Day title 4', skipOffstage: false),
      findsNothing,
    );
    expect(find.text('+2 more days', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Copy text puts the plan on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await _open(tester, _plan(2));
    await tester.tap(find.text('Copy text'));
    await tester.pump();
    expect(copied, contains('Varanasi'));
    expect(find.text('Copied'), findsOneWidget);
  });
}
