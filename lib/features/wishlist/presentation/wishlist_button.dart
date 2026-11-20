import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/location_repository.dart';
import '../../locations/domain/location.dart';
import '../application/wishlist_service.dart';
import '../data/wishlist_repository.dart';
import '../domain/wishlist_entry.dart';

/// A bookmark that saves any place to the wishlist, wherever its sheet was
/// opened from. Filled when saved; the tooltip says what a tap will do.
///
/// Places from search results or trip plans may not be stored yet, and the
/// wishlist reads saved places from the `locations` table, so saving stores
/// the place first (an existing row is left as it is).
class WishlistIconButton extends ConsumerWidget {
  const WishlistIconButton({super.key, required this.place});

  final ExploreLocation place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref
        .watch(wishlistKeysProvider)
        .maybeWhen(
          data: (keys) => isWishlisted(keys, WishlistType.location, place.id),
          orElse: () => false,
        );

    return IconButton(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      isSelected: saved,
      tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
      icon: const Icon(Icons.bookmark_outline_rounded),
      selectedIcon: const Icon(Icons.bookmark_rounded),
      color: Theme.of(context).colorScheme.primary,
      onPressed: () async {
        try {
          await toggleWishlist(ref, place);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Couldn\'t update your wishlist. Try again.'),
            ),
          );
        }
      },
    );
  }
}

/// Saves [place] to the wishlist, or removes it if already saved.
Future<void> toggleWishlist(WidgetRef ref, ExploreLocation place) async {
  await ref.read(locationRepositoryProvider).insertMany([place]);
  await ref
      .read(wishlistRepositoryProvider)
      .toggle(WishlistType.location, place.id);
  ref.invalidate(wishlistKeysProvider);
  ref.invalidate(wishlistEntriesProvider);
}
