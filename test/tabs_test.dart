import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_world_exploration/core/router/main_layout.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';
import 'package:real_world_exploration/features/social/domain/friendship.dart';
import 'package:real_world_exploration/features/tracking/application/tracking_service.dart';
import 'package:real_world_exploration/features/tracking/domain/adventure_session.dart';

class _User implements User {
  @override
  String get uid => 'me';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Social implements SocialRepository {
  _Social(this.friendships);
  final List<Friendship> friendships;
  @override
  Future<List<Friendship>> getFriendshipsFor(String uid) async => friendships;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Friendship _request(String from, {bool accepted = false}) => Friendship(
  id: '${from}_me',
  uidA: from,
  uidB: 'me',
  status: accepted ? FriendshipStatus.accepted : FriendshipStatus.pending,
  requestedBy: from,
  createdAt: DateTime(2026),
);

class _Tracking extends TrackingService {
  _Tracking(this.fixed);
  final TrackingState fixed;
  @override
  TrackingState build() => fixed;
}

/// The real shell, with a counter page in Explore to prove tab state is kept.
Future<GoRouter> _pump(
  WidgetTester tester, {
  List<Friendship> friendships = const [],
  TrackingState tracking = const TrackingState(),
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/explore',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainLayout(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, _) => const _CounterPage(),
                routes: [
                  GoRoute(
                    path: 'detail',
                    builder: (_, _) =>
                        const Scaffold(body: Text('DETAIL PAGE')),
                  ),
                ],
              ),
            ],
          ),
          for (final p in ['/map', '/trips', '/social', '/you'])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: p,
                  builder: (_, _) => Scaffold(body: Text('page$p')),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(true),
        authStateProvider.overrideWith((ref) => Stream.value(_User())),
        socialRepositoryProvider.overrideWithValue(_Social(friendships)),
        trackingServiceProvider.overrideWith(() => _Tracking(tracking)),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('count $n'),
        TextButton(
          onPressed: () => setState(() => n++),
          child: const Text('+'),
        ),
        TextButton(
          onPressed: () => context.go('/explore/detail'),
          child: const Text('open detail'),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('five labelled tabs; the current one is selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    for (final label in ['Explore', 'Map', 'Trips', 'Friends', 'You']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Explore')),
      isSemantics(label: 'Explore', isSelected: true, isButton: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Map')),
      isSemantics(label: 'Map', isSelected: false, isButton: true),
    );
    semantics.dispose();
  });

  testWidgets('a tab keeps its state when you switch away and back', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('+'));
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('count 2'), findsOneWidget);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('page/map'), findsOneWidget);
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(find.text('count 2'), findsOneWidget);
  });

  testWidgets('tapping the current tab goes back to its first screen', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL PAGE'), findsOneWidget);
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL PAGE'), findsNothing);
    expect(find.text('open detail'), findsOneWidget);
  });

  testWidgets('Back from another tab goes to Explore, not out of the app', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('page/trips'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('open detail'), findsOneWidget);
  });

  testWidgets('Back on Explore is left to the system (exits the app)', (
    tester,
  ) async {
    await _pump(tester);
    final popped = await tester.binding.handlePopRoute();
    expect(popped, isFalse);
  });

  group('Friends badge', () {
    testWidgets('counts only requests waiting for you', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        friendships: [
          _request('a'),
          _request('b'),
          _request('c', accepted: true),
        ],
      );
      expect(find.text('2'), findsOneWidget);
      // Said by the screen reader too, not just drawn.
      expect(find.bySemanticsLabel('Friends, 2 new'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no requests, no badge', (tester) async {
      await _pump(tester);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('also shows on the tablet rail', (tester) async {
      await _pump(
        tester,
        friendships: [_request('a')],
        size: const Size(1200, 900),
      );
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });

  testWidgets('the trip bar shows on every tab while a trip runs', (
    tester,
  ) async {
    await _pump(
      tester,
      tracking: TrackingState(
        session: AdventureSession(
          id: 't',
          title: 'Walk',
          startedAt: DateTime(2026),
          status: AdventureStatus.active,
        ),
      ),
    );
    expect(find.text('SOS'), findsOneWidget);
    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('SOS'), findsOneWidget);
  });

  testWidgets('no trip, no bar', (tester) async {
    await _pump(tester);
    expect(find.text('SOS'), findsNothing);
  });

  testWidgets('tabs meet size, label and contrast guidelines (badge on)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, friendships: [_request('a')]);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('fits 320 dp at 1.3x text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      size: const Size(320, 640),
      friendships: [_request('a')],
    );
    expect(tester.takeException(), isNull);
  });
}
