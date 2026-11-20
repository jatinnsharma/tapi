import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_world_exploration/core/services/firebase_status.dart';
import 'package:real_world_exploration/core/theme/app_theme.dart';
import 'package:real_world_exploration/features/album/application/album_uploader.dart';
import 'package:real_world_exploration/features/album/data/album_queue_repository.dart';
import 'package:real_world_exploration/features/album/domain/album_photo.dart';
import 'package:real_world_exploration/features/auth/application/account_eraser.dart';
import 'package:real_world_exploration/features/auth/application/auth_service.dart';
import 'package:real_world_exploration/features/auth/presentation/login_screen.dart';
import 'package:real_world_exploration/features/memories/data/shared_memory_service.dart';
import 'package:real_world_exploration/features/settings/presentation/delete_account_dialog.dart';
import 'package:real_world_exploration/features/social/data/social_repository.dart';
import 'package:real_world_exploration/features/social/domain/explorer_profile.dart';

/// Records what was deleted, in order. [failAt] makes one step throw.
class _Store implements AccountDataStore {
  _Store({this.failAt});
  final String? failAt;
  final log = <String>[];

  Future<void> _do(String step) async {
    if (step == failAt) throw StateError('offline');
    log.add(step);
  }

  @override
  Future<List<({String id, String ownerUid})>> tripsFor(String uid) async => [
    (id: 'mine', ownerUid: uid),
    (id: 'theirs', ownerUid: 'bob'),
  ];
  @override
  Future<void> deleteAlbumRecords(String tripId, {String? uploaderUid}) =>
      _do('album $tripId ${uploaderUid ?? 'all'}');
  @override
  Future<void> deleteTrip(String tripId) => _do('delete trip $tripId');
  @override
  Future<void> leaveTrip(String tripId, String uid) =>
      _do('leave trip $tripId');
  @override
  Future<void> deleteToursBy(String uid) => _do('tours');
  @override
  Future<void> deleteTipsBy(String uid) => _do('tips');
  @override
  Future<void> deleteChallengesOf(String uid) => _do('challenges');
  @override
  Future<List<({String id, bool created})>> groupsOf(String uid) async => [
    (id: 'g1', created: true),
    (id: 'g2', created: false),
  ];
  @override
  Future<void> deleteGroup(String id) => _do('delete group $id');
  @override
  Future<void> leaveGroup(String id, String uid) => _do('leave group $id');
  @override
  Future<List<({String id, bool created})>> meetupsOf(String uid) async => [
    (id: 'm1', created: false),
  ];
  @override
  Future<void> deleteMeetup(String id) => _do('delete meetup $id');
  @override
  Future<void> leaveMeetup(String id, String uid) => _do('leave meetup $id');
  @override
  Future<void> deleteAvatar(String uid) => _do('avatar');
  @override
  Future<void> deleteSocialData(String uid) => _do('profile');
}

class _User implements User {
  @override
  String get uid => 'me';
  @override
  String? get displayName => null;
  @override
  String? get email => 'jatin.private.1990@example.com';
  @override
  String? get photoURL => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthService {
  _Auth({this.signInError, this.reauthError, this.password = true});
  final String? signInError;
  final String? reauthError;
  final bool password;
  final calls = <String>[];
  String? signedUpName;

  @override
  Future<User?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    calls.add('signUp');
    signedUpName = name;
    return _User();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn');
    if (signInError != null) throw FirebaseAuthException(code: signInError!);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      calls.add('reset $email');

  @override
  bool get usesPassword => password;

  @override
  Future<void> reauthenticate(String? password) async {
    calls.add('reauth');
    if (reauthError != null) throw FirebaseAuthException(code: reauthError!);
  }

  @override
  Future<void> deleteCurrentUser() async => calls.add('delete user');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Social implements SocialRepository {
  _Social({this.fail = false});
  final bool fail;
  final created = <ExplorerProfile>[];
  @override
  Future<ExplorerProfile?> getProfile(String uid) async {
    if (fail) throw StateError('offline');
    return null;
  }

  @override
  Future<void> upsertProfile(ExplorerProfile profile) async =>
      created.add(profile);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Memories implements SharedMemoryService {
  _Memories(this.log);
  final List<String> log;
  @override
  Future<void> deleteAllFor(String uid) async => log.add('shared memories');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Queue implements AlbumQueueRepository {
  @override
  Future<List<QueuedPhoto>> withDriveCopies() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Uploader implements AlbumUploader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('erasing account data', () {
    test('owned trips go, with their album; others\' trips are left', () async {
      final store = _Store();
      await eraseAccountData(store, 'me');
      expect(store.log, [
        'album mine all',
        'delete trip mine',
        'album theirs me',
        'leave trip theirs',
        'tours',
        'tips',
        'challenges',
        'delete group g1',
        'leave group g2',
        'leave meetup m1',
        'avatar',
        'profile',
      ]);
    });

    test('a failure stops before the profile, so a retry can finish', () async {
      final store = _Store(failAt: 'tips');
      await expectLater(eraseAccountData(store, 'me'), throwsStateError);
      expect(store.log, isNot(contains('profile')));
      expect(store.log.last, 'tours');
    });
  });

  group('form checks', () {
    test('emails', () {
      expect(looksLikeEmail('asha@example.com'), isTrue);
      expect(looksLikeEmail(' asha@example.com '), isTrue);
      expect(looksLikeEmail('asha@'), isFalse);
      expect(looksLikeEmail('asha@example'), isFalse);
      expect(looksLikeEmail('a sha@example.com'), isFalse);
    });

    test('names', () {
      expect(nameProblem(''), 'Enter your name');
      expect(nameProblem(' A '), 'Enter your name');
      expect(nameProblem('Asha'), isNull);
      expect(nameProblem('x' * 41), 'At most 40 characters');
    });

    test('new error codes read as plain words', () {
      expect(friendlyAuthCode('operation-not-allowed'), contains("isn't"));
      expect(friendlyAuthCode('requires-recent-login'), contains('sign in'));
    });
  });

  group('login screen', () {
    Future<(_Auth, _Social)> pump(
      WidgetTester tester, {
      _Auth? auth,
      _Social? social,
    }) async {
      final a = auth ?? _Auth();
      final s = social ?? _Social();
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
            authServiceProvider.overrideWithValue(a),
            socialRepositoryProvider.overrideWithValue(s),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      return (a, s);
    }

    Future<void> toSignUp(WidgetTester tester) async {
      await tester.ensureVisible(
        find.text("Don't have an account? Create one"),
      );
      await tester.tap(find.text("Don't have an account? Create one"));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String label, String value) =>
        tester.enterText(find.widgetWithText(TextFormField, label), value);

    Future<void> press(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('signing up asks for a name and checks the fields', (
      tester,
    ) async {
      final (auth, _) = await pump(tester);
      await toSignUp(tester);
      expect(find.text('Your name'), findsOneWidget);
      await fill(tester, 'Email', 'asha@');
      await fill(tester, 'Password', '123');
      await press(tester, 'Create account');
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('At least 6 characters'), findsWidgets);
      expect(auth.calls, isEmpty);
    });

    testWidgets('the profile uses the name typed, never the email', (
      tester,
    ) async {
      final (auth, social) = await pump(tester);
      await toSignUp(tester);
      await fill(tester, 'Your name', '  Jatin  ');
      await fill(tester, 'Email', 'jatin.private.1990@example.com');
      await fill(tester, 'Password', 'secret123');
      await press(tester, 'Create account');
      expect(auth.signedUpName, 'Jatin');
      expect(social.created.single.displayName, 'Jatin');
      expect(find.text('open login'), findsOneWidget, reason: 'went back');
    });

    testWidgets('signed up even when the profile can\'t be saved yet', (
      tester,
    ) async {
      final (_, _) = await pump(tester, social: _Social(fail: true));
      await toSignUp(tester);
      await fill(tester, 'Your name', 'Asha');
      await fill(tester, 'Email', 'asha@example.com');
      await fill(tester, 'Password', 'secret123');
      await press(tester, 'Create account');
      // No scary error: the account exists and the user is signed in.
      expect(find.text('open login'), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines, sign-in and sign-up', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await toSignUp(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('fits 320 dp at 1.3x text, sign-up too', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      await toSignUp(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong password says so and stays', (tester) async {
      await pump(tester, auth: _Auth(signInError: 'invalid-credential'));
      await fill(tester, 'Email', 'asha@example.com');
      await fill(tester, 'Password', 'wrong-pass');
      await press(tester, 'Sign in');
      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(find.text('open login'), findsNothing);
    });

    testWidgets('forgot password sends a link without saying who exists', (
      tester,
    ) async {
      final (auth, _) = await pump(tester);
      await fill(tester, 'Email', 'asha@example.com');
      await press(tester, 'Forgot password?');
      expect(find.text('Reset password'), findsOneWidget);
      await press(tester, 'Send link');
      expect(auth.calls, ['reset asha@example.com']);
      expect(find.textContaining("If there's an account"), findsOneWidget);
    });
  });

  group('delete account dialog', () {
    Future<(_Auth, _Store, List<String>)> pump(
      WidgetTester tester, {
      _Auth? auth,
      _Store? store,
    }) async {
      final a = auth ?? _Auth();
      final s = store ?? _Store();
      final memoriesLog = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(a),
            accountDataStoreProvider.overrideWithValue(s),
            sharedMemoryServiceProvider.overrideWithValue(
              _Memories(memoriesLog),
            ),
            albumQueueRepositoryProvider.overrideWithValue(_Queue()),
            albumUploaderProvider.overrideWithValue(_Uploader()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDeleteAccountDialog(context, 'me'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (a, s, memoriesLog);
    }

    testWidgets('says what goes and what stays', (tester) async {
      await pump(tester);
      expect(find.text('This permanently deletes:'), findsOneWidget);
      expect(find.textContaining('profile photo'), findsOneWidget);
      expect(find.textContaining('Trips you saved'), findsOneWidget);
      expect(find.text('What stays:'), findsOneWidget);
      expect(find.textContaining('verified XP'), findsOneWidget);
    });

    testWidgets('needs the password first', (tester) async {
      await pump(tester);
      final button = find.widgetWithText(FilledButton, 'Delete my account');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('confirms, removes the data, then the sign-in', (tester) async {
      final (auth, store, memories) = await pump(tester);
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.pump();
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['reauth', 'delete user']);
      expect(memories, ['shared memories']);
      expect(store.log.last, 'profile');
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });

    testWidgets('a wrong password deletes nothing', (tester) async {
      final (auth, store, memories) = await pump(
        tester,
        auth: _Auth(reauthError: 'wrong-password'),
      );
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pump();
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(find.text('That password is incorrect.'), findsOneWidget);
      expect(store.log, isEmpty);
      expect(memories, isEmpty);
      expect(auth.calls, ['reauth']);
    });

    testWidgets('a failure keeps the sign-in, so trying again finishes', (
      tester,
    ) async {
      final (auth, _, _) = await pump(tester, store: _Store(failAt: 'tips'));
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.pump();
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(auth.calls, isNot(contains('delete user')));
      expect(find.textContaining("Couldn't finish deleting"), findsOneWidget);
    });

    testWidgets('Google accounts confirm with Google, no password box', (
      tester,
    ) async {
      await pump(tester, auth: _Auth(password: false));
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('confirm with Google'), findsOneWidget);
    });
  });
}
