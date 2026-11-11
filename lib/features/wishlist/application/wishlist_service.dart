import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wishlist_repository.dart';
import '../domain/wishlist_entry.dart';

/// Set of "type:id" keys currently saved, for cheap `.contains` checks in UI.
final wishlistKeysProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final entries = await ref.watch(wishlistRepositoryProvider).getAll();
  return entries.map((e) => e.key).toSet();
});

final wishlistEntriesProvider = FutureProvider.autoDispose<List<WishlistEntry>>(
  (ref) {
    return ref.watch(wishlistRepositoryProvider).getAll();
  },
);

bool isWishlisted(Set<String> keys, WishlistType type, String id) {
  return keys.contains('${type.name}:$id');
}
