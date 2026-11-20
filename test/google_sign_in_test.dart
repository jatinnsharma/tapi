import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/auth/presentation/login_screen.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';
import 'package:real_world_exploration/features/social/domain/explorer_profile.dart';

class _FakeUser implements User {
  @override
  String get uid => 'g-user';
  @override
  String? get displayName => 'Asha Verma';
  @override
  String? get email => 'asha@example.com';
  @override
  String? get photoURL => 'https://example.com/a.jpg';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  _FakeAuth({this.failWith});

  final String? failWith;

  @override
  Future<User?> signInWithGoogle() async {
    if (failWith != null) throw FirebaseAuthException(code: failWith!);
    return _FakeUser();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocial implements SocialRepository {
  _FakeSocial({this.existing});

  final ExplorerProfile? existing;
  final created = <ExplorerProfile>[];

  @override
  Future<ExplorerProfile?> getProfile(String uid) async => existing;
  @override
  Future<void> upsertProfile(ExplorerProfile profile) async =>
      created.add(profile);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('closing the Google window says nothing; real failures explain', () {
    expect(googleSignInError('web-context-canceled'), isNull);
    expect(googleSignInError('popup-closed-by-user'), isNull);
    expect(
      googleSignInError('account-exists-with-different-credential'),
      contains('email and password'),
    );
    expect(googleSignInError('operation-not-allowed'), contains("isn't"));
    expect(googleSignInError('weird'), contains('weird'));
  });

  Future<_FakeSocial> pump(
    WidgetTester tester, {
    String? failWith,
    ExplorerProfile? existing,
  }) async {
    final social = _FakeSocial(existing: existing);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('open login'),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(true),
          authServiceProvider.overrideWithValue(_FakeAuth(failWith: failWith)),
          socialRepositoryProvider.overrideWithValue(social),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open login'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    return social;
  }

  testWidgets('first Google sign-in creates the profile and goes back', (
    tester,
  ) async {
    final social = await pump(tester);
    expect(social.created.single.displayName, 'Asha Verma');
    expect(social.created.single.photoUrl, 'https://example.com/a.jpg');
    expect(find.text('open login'), findsOneWidget); // Back where we were.
  });

  testWidgets('an existing profile is not overwritten', (tester) async {
    final social = await pump(
      tester,
      existing: ExplorerProfile(
        uid: 'g-user',
        displayName: 'Edited name',
        createdAt: DateTime(2026),
      ),
    );
    expect(social.created, isEmpty);
  });

  testWidgets('a cancelled Google window stays quiet on the login screen', (
    tester,
  ) async {
    await pump(tester, failWith: 'web-context-canceled');
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.textContaining('Could not'), findsNothing);
  });

  test('sign-in errors read as plain words, never raw Firebase text', () {
    expect(friendlyAuthError('wrong-password'), 'Wrong email or password.');
    expect(friendlyAuthError('invalid-credential'), 'Wrong email or password.');
    expect(friendlyAuthError('email-already-in-use'), contains('Sign in'));
    expect(
      friendlyAuthError('something-new'),
      "Couldn't sign in. Please try again.",
    );
  });

  testWidgets('login has a way out and a show-password toggle', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('open login'),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open login'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('open login'), findsOneWidget);
  });
}
