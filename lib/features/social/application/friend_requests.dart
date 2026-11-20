import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_status.dart';
import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/friendship.dart';

/// Your friendships (accepted and pending). Empty when signed out or
/// without Firebase.
final friendshipsProvider = FutureProvider.autoDispose<List<Friendship>>((
  ref,
) async {
  if (!ref.watch(firebaseReadyProvider)) return [];
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return [];
  return ref.watch(socialRepositoryProvider).getFriendshipsFor(uid);
});

/// How many people are waiting for you to accept their friend request (the
/// badge on the Friends tab).
final incomingRequestCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return 0;
  final friendships = ref.watch(friendshipsProvider).value ?? const [];
  return friendships.where((f) => f.isIncomingFor(uid)).length;
});
