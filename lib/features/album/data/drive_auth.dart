import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/google_drive.dart';

/// Access to the user's Google Drive, separate from how they sign in to the
/// app (it can even be another Google account).
abstract class DriveAuth {
  /// A current access token, or null when Drive isn't connected and
  /// [interactive] is false. With [interactive], asks the user to connect
  /// (only call from a button tap).
  Future<String?> token({bool interactive = false});

  /// Forgets a token Drive rejected, so the next [token] gets a fresh one.
  Future<void> invalidate(String token);

  /// Disconnects Drive from the app.
  Future<void> disconnect();
}

/// [DriveAuth] with Google's official sign-in package and only the
/// `drive.file` scope: the app sees the files it creates, nothing else.
class GoogleDriveAuth implements DriveAuth {
  static const scope = 'https://www.googleapis.com/auth/drive.file';

  Future<void>? _init;
  GoogleSignInAccount? _account;

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize(
    serverClientId: googleServerClientId.isEmpty ? null : googleServerClientId,
  );

  @override
  Future<String?> token({bool interactive = false}) async {
    if (!driveAlbumConfigured) return null;
    await _ready();
    _account ??=
        await (GoogleSignIn.instance.attemptLightweightAuthentication() ??
            Future<GoogleSignInAccount?>.value());
    var account = _account;
    if (account == null) {
      if (!interactive) return null;
      account = _account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [scope],
      );
    }
    final existing = await account.authorizationClient.authorizationForScopes(
      const [scope],
    );
    if (existing != null) return existing.accessToken;
    if (!interactive) return null;
    final granted = await account.authorizationClient.authorizeScopes(const [
      scope,
    ]);
    return granted.accessToken;
  }

  @override
  Future<void> invalidate(String token) async {
    await _ready();
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
  }

  @override
  Future<void> disconnect() async {
    await _ready();
    _account = null;
    await GoogleSignIn.instance.disconnect();
  }
}

final driveAuthProvider = Provider<DriveAuth>((ref) => GoogleDriveAuth());

/// Whether Drive is connected right now (no prompts). Refresh by
/// invalidating after connecting or disconnecting.
final driveConnectedProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(driveAuthProvider).token() != null;
  } catch (_) {
    return false;
  }
});

/// Whether this build has Google Drive albums set up (overridable in tests).
final driveConfiguredProvider = Provider<bool>((ref) => driveAlbumConfigured);
