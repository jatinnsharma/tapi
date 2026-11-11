import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_status.dart';
import 'auth_service.dart';

/// First name (or email prefix) of the signed-in user, for greetings.
/// Null when Firebase isn't configured or nobody is signed in.
final displayNameProvider = Provider.autoDispose<String?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  final user = ref.watch(authStateProvider).value;
  final name = user?.displayName;
  if (name != null && name.trim().isNotEmpty) {
    return name.trim().split(' ').first;
  }
  final email = user?.email;
  if (email != null && email.contains('@')) return email.split('@').first;
  return null;
});
