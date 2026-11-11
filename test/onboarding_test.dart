import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  testWidgets('OnboardingScreen renders first page with Skip and Continue', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OnboardingScreen())),
    );

    expect(find.text('Welcome to Tabi'), findsOneWidget);
    expect(find.text('Turn every step into an adventure'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // Tap Continue to go to Page 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('How XP Works'), findsOneWidget);
    expect(find.text('Real walking & authentic visits'), findsOneWidget);

    // Tap Continue to go to Page 3
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Why Location Matters'), findsOneWidget);
    expect(find.text('Enable Location & Start Exploring'), findsOneWidget);
  });
}
