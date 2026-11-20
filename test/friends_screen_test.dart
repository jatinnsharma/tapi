import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/social/application/friend_challenge_service.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';
import 'package:real_world_exploration/features/social/domain/explorer_profile.dart';
import 'package:real_world_exploration/features/social/domain/friendship.dart';
import 'package:real_world_exploration/features/social/domain/live_location.dart';
import 'package:real_world_exploration/features/social/presentation/social_screen.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';
  @override
  String? get email => 'me@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExplorerProfile _p(String uid, String name) =>
    ExplorerProfile(uid: uid, displayName: name, createdAt: DateTime(2026));

Friendship _f(String other, FriendshipStatus status, {String? by}) =>
    Friendship(
      id: 'me_$other',
      uidA: 'me',
      uidB: other,
      status: status,
      requestedBy: by ?? 'me',
      createdAt: DateTime(2026),
    );

class _FakeSocial extends Fake implements SocialRepository {
  // "Zara" is a friend outside the first page of explorers.
  final explorers = [_p('a', 'Asha'), _p('b', 'Bilal'), _p('c', 'Chen')];
  final extra = {'z': _p('z', 'Zara'), 'r': _p('r', 'Ravi')};
  final friendships = [
    _f('a', FriendshipStatus.accepted),
    _f('z', FriendshipStatus.accepted),
    _f('b', FriendshipStatus.pending),
    _f('r', FriendshipStatus.pending, by: 'r'),
  ];

  @override
  Future<List<ExplorerProfile>> getAllExplorers({
    required String excludingUid,
  }) async => explorers;

  @override
  Future<List<Friendship>> getFriendshipsFor(String uid) async => friendships;

  @override
  Future<ExplorerProfile?> getProfile(String uid) async =>
      uid == 'me' ? _p('me', 'Me') : extra[uid];

  @override
  Future<List<LiveLocation>> getFriendsLiveLocations(
    List<String> friendUids,
  ) async => const [];

  @override
  Future<Set<String>> getBlockedUids(String myUid) async => {};

  @override
  Future<Set<String>> getUidsWhoBlockedMe(String myUid) async => {};

  @override
  Future<Set<String>> getMutedUids(String myUid) async => {};
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(true),
        authStateProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        socialRepositoryProvider.overrideWithValue(_FakeSocial()),
        friendChallengesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SocialScreen()),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('labelled shortcuts replace the four header icons', (
    tester,
  ) async {
    await _pump(tester);
    for (final label in ['Groups', 'Meetups', 'Leaderboard', 'Feed']) {
      expect(find.widgetWithText(ActionChip, label), findsOneWidget);
    }
    // Account and privacy live in Settings now.
    expect(find.text('Account settings'), findsNothing);
    expect(find.text('Who can see my map'), findsNothing);
  });

  testWidgets('requests have labelled Accept and Decline, with real names', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Requests (1)'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('An explorer'), findsNothing);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('friends get their own list, even beyond the first explorers', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Your friends (2)'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Zara'), findsOneWidget);
    // Bilal has a pending request from me; Chen can be added.
    expect(find.text('Requested'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('search narrows Find explorers by name', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'che');
    await tester.pump();
    expect(find.text('Chen'), findsOneWidget);
    expect(find.text('Bilal'), findsNothing);
    // Friends stay listed above, unaffected.
    expect(find.text('Asha'), findsOneWidget);
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
