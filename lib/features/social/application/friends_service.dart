import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/explorer_profile.dart';

final acceptedFriendsProvider =
    FutureProvider.autoDispose<List<ExplorerProfile>>((ref) async {
      final user = ref.watch(authStateProvider).value;
      if (user == null) return const [];
      final social = ref.watch(socialRepositoryProvider);
      final friendships = await social.getFriendshipsFor(user.uid);
      final friendUids = [
        for (final f in friendships)
          if (f.isAccepted) f.otherUid(user.uid),
      ];
      final profiles = await Future.wait(friendUids.map(social.getProfile));
      return [for (final p in profiles) ?p];
    });
