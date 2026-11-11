import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';
import 'package:real_world_exploration/features/tracking/presentation/trip_not_counted_checklist.dart';

void main() {
  testWidgets(
    'TripNotCountedChecklist displays failed checklist when too short',
    (tester) async {
      final session = AdventureSession(
        id: 'test-session-1',
        title: 'Short Walk',
        startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        endedAt: DateTime.now(),
        status: AdventureStatus.unverified,
        trekMeters: 50,
        trekSeconds: 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripNotCountedChecklist(
              session: session,
              xpNotice: 'This trip had too little trekking to count.',
            ),
          ),
        ),
      );

      expect(find.text('Trip requirements checklist'), findsOneWidget);
      expect(find.text('Walked ≥ 200 m on trek (50 m)'), findsOneWidget);
      expect(find.text('Trek lasted ≥ 3 min (1m 0s)'), findsOneWidget);
      expect(find.text('How XP works'), findsOneWidget);

      // Tap "How XP works" to ensure modal opens
      await tester.tap(find.text('How XP works'));
      await tester.pumpAndSettle();

      expect(find.text('How Tabi XP Works'), findsOneWidget);
      expect(find.text('Minimum 200 m & 3 minutes'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('How Tabi XP Works'), findsNothing);
    },
  );
}
