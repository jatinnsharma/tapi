import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_world_exploration/core/router/main_layout.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/core/theme/components.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';

class _NoTrip extends TrackingService {
  @override
  TrackingState build() => const TrackingState();
}

/// The real shell with a plain page per tab.
Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  StatefulShellBranch branch(String path) => StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (_, _) => SizedBox.expand(
          key: ValueKey('page$path'),
          child: Text('page$path'),
        ),
      ),
    ],
  );
  final router = GoRouter(
    initialLocation: '/explore',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainLayout(navigationShell: shell),
        branches: [
          for (final p in ['/explore', '/map', '/trips', '/social', '/you'])
            branch(p),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [trackingServiceProvider.overrideWith(_NoTrip.new)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phones keep the bottom bar', (tester) async {
    await _pumpShell(tester, const Size(400, 800));
    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('tablets get a side rail and pages capped at 720', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(1200, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(FloatingNavBar), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('page/explore'))).width,
      MainLayout.maxContentWidth,
    );

    // The map uses the whole width next to the rail.
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('page/map'))).width,
      greaterThan(1000),
    );
  });

  testWidgets('the rail is labelled and tappable', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpShell(tester, const Size(1200, 900));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
