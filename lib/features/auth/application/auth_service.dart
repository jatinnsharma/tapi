import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Emits the current signed-in user (or null), updating live on sign-in/out.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Creates the account and sets [name] as its display name (shown to
  /// friends instead of anything from the email address).
  Future<User?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    try {
      await user?.updateDisplayName(name);
      await user?.reload();
    } catch (_) {
      // The account exists; the name can be set later from the profile.
    }
    return _auth.currentUser ?? user;
  }

  /// Signs in with a Google account, in Firebase's own Google flow (a
  /// browser tab on phones, a popup on the web), so no extra package is
  /// needed. Returns the user, or throws [FirebaseAuthException]; see
  /// [googleSignInError] for what each failure means.
  Future<User?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    final credential = kIsWeb
        ? await _auth.signInWithPopup(provider)
        : await _auth.signInWithProvider(provider);
    return credential.user;
  }

  /// Whether the signed-in account has a password (email sign-up) rather
  /// than only Google.
  bool get usesPassword =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ??
      false;

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  /// Confirms it's really the user: their password, or for a Google-only
  /// account, signing in with Google again ([password] is then ignored).
  /// Firebase only allows deleting an account after a recent sign-in, and
  /// asking again guards against someone else deleting an account on an
  /// unlocked phone. Throws [FirebaseAuthException] (e.g. `wrong-password`,
  /// `invalid-credential`, `web-context-canceled`).
  Future<void> reauthenticate(String? password) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in account.');
    if (!usesPassword) {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await user.reauthenticateWithPopup(provider);
      } else {
        await user.reauthenticateWithProvider(provider);
      }
      return;
    }
    final email = user.email;
    if (email == null || password == null) {
      throw StateError('No password to check.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  /// Deletes the sign-in account itself. Call after [reauthenticate] and
  /// after the user's data has been removed.
  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }
}

/// What to tell the user when Google sign-in fails with [code], or null
/// when they simply closed the Google window (say nothing).
String? googleSignInError(String code) => switch (code) {
  'web-context-canceled' ||
  'web-context-cancelled' ||
  'popup-closed-by-user' ||
  'cancelled-popup-request' ||
  'canceled' => null,
  'account-exists-with-different-credential' =>
    'This email already has a Tabi account with a password. Sign in with '
        'your email and password instead.',
  'operation-not-allowed' =>
    "Google sign-in isn't switched on for this app yet.",
  'network-request-failed' => 'No connection. Check your internet and retry.',
  'user-disabled' => 'This account has been disabled.',
  _ => 'Could not sign in with Google ($code). Please try again.',
};

/// Plain words for a Firebase sign-in error [code] (never the raw message).
String friendlyAuthCode(String code) => switch (code) {
  'invalid-email' => "That email address doesn't look right.",
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' ||
  'INVALID_LOGIN_CREDENTIALS' => 'Wrong email or password.',
  'email-already-in-use' =>
    'An account with this email already exists. Sign in instead.',
  'weak-password' => 'Choose a longer password (at least 6 characters).',
  'too-many-requests' => 'Too many tries. Wait a minute and try again.',
  'network-request-failed' => 'No connection. Check your internet and retry.',
  'user-disabled' => 'This account has been disabled.',
  'operation-not-allowed' =>
    "This way of signing in isn't switched on for the app yet.",
  'requires-recent-login' => 'For safety, sign in again and retry.',
  _ => "Couldn't sign in. Please try again.",
};

/// A sensible email: something@something.something, no spaces.
bool looksLikeEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

/// The name explorers see: 2 to 40 characters once trimmed.
String? nameProblem(String? value) {
  final name = value?.trim() ?? '';
  if (name.length < 2) return 'Enter your name';
  if (name.length > 40) return 'At most 40 characters';
  return null;
}
