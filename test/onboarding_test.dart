import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_world_exploration/core/services/location_service.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/onboarding/application/onboarding_service.dart';
import 'package:real_world_exploration/features/onboarding/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Permission extends LocationService {
  _Permission({this.fail = false});
  final bool fail;
  var asked = 0;

  @override
  Future<bool> requestPermission() async {
    asked++;
    // Like the real prompt, it takes a moment.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (fail) throw StateError('A request for permissions is already running');
    return true;
  }
}

/// Onboarding inside a tiny router, so "go to Explore" can be seen.
Future<(_Permission, ProviderContainer)> _pump(
  WidgetTester tester, {
  bool failPermission = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final permission = _Permission(fail: failPermission);
  final container = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(permission),
      onboardingCompletedProvider.overrideWith(
        () => OnboardingNotifier(initial: false),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/explore',
        builder: (_, _) => const Scaffold(body: Text('EXPLORE')),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (permission, container);
}

Future<void> _toLastPage(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('three pages, with Skip and Continue', (tester) async {
    await _pump(tester);
    expect(find.text('Welcome to Tabi'), findsOneWidget);
    expect(find.text('Turn every step into an adventure'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How XP Works'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Why Location Matters'), findsOneWidget);
    expect(find.text('Enable Location & Start Exploring'), findsOneWidget);
  });

  testWidgets('swiping also moves between pages', (tester) async {
    await _pump(tester);
    await tester.fling(
      find.text('Welcome to Tabi'),
      const Offset(-400, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('How XP Works'), findsOneWidget);
  });

  testWidgets('Skip finishes without asking for location', (tester) async {
    final (permission, container) = await _pump(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORE'), findsOneWidget);
    expect(permission.asked, 0);
    expect(container.read(onboardingCompletedProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed_v1'), isTrue);
  });

  testWidgets('the last button asks for location once, then opens Explore', (
    tester,
  ) async {
    final (permission, _) = await _pump(tester);
    await _toLastPage(tester);
    final button = find.text('Enable Location & Start Exploring');
    await tester.tap(button);
    await tester.pump();
    // A second tap while it's finishing is ignored.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(permission.asked, 1);
    expect(find.text('EXPLORE'), findsOneWidget);
  });

  testWidgets('a failed permission request never leaves you stuck', (
    tester,
  ) async {
    final (permission, container) = await _pump(tester, failPermission: true);
    await _toLastPage(tester);
    await tester.tap(find.text('Enable Location & Start Exploring'));
    await tester.pumpAndSettle();
    expect(permission.asked, 1);
    expect(find.text('EXPLORE'), findsOneWidget);
    expect(container.read(onboardingCompletedProvider), isTrue);
  });

  testWidgets('fits a 320 dp phone at 1.3x text on every page', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    expect(tester.takeException(), isNull);
    await _toLastPage(tester);
    expect(tester.takeException(), isNull);
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

  group('start-up', () {
    test('a new install has not done onboarding', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await readOnboardingCompleted(), isFalse);
    });

    test('after finishing, it stays finished', () async {
      SharedPreferences.setMockInitialValues({'onboarding_completed_v1': true});
      expect(await readOnboardingCompleted(), isTrue);
    });

    test('a new user starts on onboarding; a returning one on Explore', () {
      expect(startLocation(onboarded: false), '/onboarding');
      expect(startLocation(onboarded: true), '/explore');
    });

    test('until onboarding is done, every screen leads back to it', () {
      expect(
        onboardingRedirect(onboarded: false, location: '/explore'),
        '/onboarding',
      );
      expect(
        onboardingRedirect(onboarded: false, location: '/trips/t1'),
        '/onboarding',
      );
      expect(
        onboardingRedirect(onboarded: false, location: '/onboarding'),
        isNull,
      );
      expect(onboardingRedirect(onboarded: true, location: '/explore'), isNull);
    });

    test('the start-up value is used straight away (no flash of Explore)', () {
      final c = ProviderContainer(
        overrides: [
          onboardingCompletedProvider.overrideWith(
            () => OnboardingNotifier(initial: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(onboardingCompletedProvider), isFalse);
    });
  });
}
