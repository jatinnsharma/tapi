import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/locations/data/location_community_repository.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/locations/domain/location_tip.dart';
import 'package:real_world_exploration/features/locations/presentation/location_tips_section.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

LocationTip _tip(String id, String uid, String text) => LocationTip(
  id: id,
  uid: uid,
  displayName: 'User $uid',
  text: text,
  timestamp: DateTime(2026, 11, 1),
);

class _FakeUser implements User {
  @override
  String get uid => 'me';
  @override
  String? get email => 'me@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCommunity implements LocationCommunityRepository {
  _FakeCommunity(this.tips);

  List<LocationTip> tips;
  final deleted = <String>[];
  final reported = <String>[];

  @override
  Future<int> getExplorerCount(String locationId) async => 3;
  @override
  Future<List<LocationTip>> getTips(String locationId) async => tips;
  @override
  Future<void> deleteTip(String locationId, String tipId) async {
    deleted.add(tipId);
    tips = [
      for (final t in tips)
        if (t.id != tipId) t,
    ];
  }

  @override
  Future<void> reportTip({
    required String locationId,
    required LocationTip tip,
    required String reportedBy,
    required String reason,
  }) async => reported.add('${tip.id}:$reason');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocial implements SocialRepository {
  final blocked = <String>{};

  @override
  Future<Set<String>> getBlockedUids(String myUid) async => blocked;
  @override
  Future<void> blockUser(String myUid, String targetUid) async =>
      blocked.add(targetUid);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _place = ExploreLocation(
  id: 'wiki-ghat',
  name: 'Assi Ghat',
  category: LocationCategory.heritage,
  description: '',
  latitude: 25.29,
  longitude: 83.0,
);

void main() {
  test('blocked authors and reported tips are hidden', () {
    final tips = [
      _tip('1', 'a', 'x'),
      _tip('2', 'b', 'y'),
      _tip('3', 'c', 'z'),
    ];
    expect(
      visibleTips(
        tips,
        hiddenAuthors: {'b'},
        reportedTipIds: {'3'},
      ).map((t) => t.id),
      ['1'],
    );
    expect(visibleTips(tips), hasLength(3));
  });

  /// Lets a reload finish: it awaits mocked plugins outside of frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<(_FakeCommunity, _FakeSocial)> pump(
    WidgetTester tester, {
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final community = _FakeCommunity([
      _tip('mine', 'me', 'Go at sunrise'),
      _tip('theirs', 'other', 'Boats are cheaper after 6'),
    ]);
    final social = _FakeSocial();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(true),
          authStateProvider.overrideWith(
            (ref) => Stream.value(signedIn ? _FakeUser() : null),
          ),
          locationCommunityRepositoryProvider.overrideWithValue(community),
          socialRepositoryProvider.overrideWithValue(social),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LocationTipsSection(location: _place)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (community, social);
  }

  testWidgets('signed out: a message, not an endless loader', (tester) async {
    await pump(tester, signedIn: false);
    expect(
      find.text('Sign in to see and share tips about this place.'),
      findsOneWidget,
    );
    // Not a dead end: a button to sign in.
    expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
    expect(find.text('Add Tip'), findsNothing);
  });

  testWidgets('own tips can be deleted', (tester) async {
    final (community, _) = await pump(tester);
    expect(find.text('3 explorers'), findsOneWidget);
    expect(find.byTooltip('Delete my tip'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete my tip'));
    await settle(tester);
    expect(community.deleted, ['mine']);
    expect(find.textContaining('Go at sunrise'), findsNothing);
  });

  testWidgets("reporting hides someone's tip for me", (tester) async {
    final (community, _) = await pump(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report tip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam or advertising'));
    await settle(tester);
    expect(community.reported, ['theirs:Spam or advertising']);
    expect(find.textContaining('Boats are cheaper'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(reportedTipsKey), ['theirs']);
  });

  testWidgets('blocking hides all of their tips', (tester) async {
    final (_, social) = await pump(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block author'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await settle(tester);
    expect(social.blocked, {'other'});
    expect(find.textContaining('Boats are cheaper'), findsNothing);
  });
}
