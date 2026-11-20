import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../locations/data/location_repository.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/place_sheet.dart';
import '../../locations/presentation/place_style.dart';
import '../../tracking/data/adventure_repository.dart';
import '../application/wishlist_service.dart';
import '../data/wishlist_repository.dart';
import '../domain/wishlist_entry.dart';
import '../../../core/ui/confirm_destructive.dart';
import '../../../core/ui/friendly_error.dart';

/// Saved places. (Saved quests from earlier versions are ignored: quests
/// aren't part of version 1.)
final _resolvedWishlistProvider =
    FutureProvider.autoDispose<List<ExploreLocation>>((ref) async {
      final entries = await ref.watch(wishlistEntriesProvider.future);
      final locationIds = entries
          .where((e) => e.type == WishlistType.location)
          .map((e) => e.targetId)
          .toSet();
      // Looked up by id, so saved food, trek or waterfall places (which the
      // map and Home leave out) still show here.
      final saved = await ref
          .watch(locationRepositoryProvider)
          .getByIds(locationIds);
      // Keep the order they were saved in.
      final byId = {for (final l in saved) l.id: l};
      return [
        for (final e in entries)
          if (e.type == WishlistType.location && byId[e.targetId] != null)
            byId[e.targetId]!,
      ];
    });

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlistAsync = ref.watch(_resolvedWishlistProvider);
    final visitedIds =
        ref.watch(visitedPlaceIdsProvider).value ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: wishlistAsync.when(
        loading: () => const _WishlistSkeleton(),
        error: (error, stack) => ListView(
          padding: AppSpacing.page,
          children: [
            EmptyStateCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load wishlist',
              message: friendlyError(error),
              actionLabel: 'Try again',
              onAction: () {
                ref.invalidate(wishlistEntriesProvider);
                ref.invalidate(_resolvedWishlistProvider);
              },
            ),
          ],
        ),
        data: (places) {
          if (places.isEmpty) {
            return ListView(
              padding: AppSpacing.page,
              children: const [
                EmptyStateCard(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Nothing saved yet',
                  message: 'Tap the bookmark on a place to save it.',
                ),
              ],
            );
          }
          return RefreshIndicator(
            color: AppTheme.forest,
            onRefresh: () async {
              ref.invalidate(wishlistEntriesProvider);
              ref.invalidate(_resolvedWishlistProvider);
            },
            child: ListView(
              padding: AppSpacing.page,
              children: [
                const SectionHeader(title: 'Places'),
                for (final location in places)
                  _WishlistRow(
                    gradient: location.category.gradient,
                    icon: location.category.icon,
                    title: location.nameFor(visitedIds),
                    subtitle: location.isHiddenMystery(visitedIds)
                        ? 'Mystery · Tap to start'
                        : '${location.category.label} · Tap to start',
                    onTap: () => showPlaceSheet(context, place: location),
                    onRemove: () async {
                      final repository = ref.read(wishlistRepositoryProvider);
                      void refresh() {
                        ref.invalidate(wishlistKeysProvider);
                        ref.invalidate(wishlistEntriesProvider);
                        ref.invalidate(_resolvedWishlistProvider);
                      }

                      await repository.remove(
                        WishlistType.location,
                        location.id,
                      );
                      refresh();
                      if (!context.mounted) return;
                      showUndoSnackBar(
                        context,
                        message:
                            '${location.nameFor(visitedIds)} removed from your '
                            'wishlist',
                        onUndo: () async {
                          await repository.add(
                            WishlistType.location,
                            location.id,
                          );
                          refresh();
                        },
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WishlistRow extends StatelessWidget {
  const _WishlistRow({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    this.onTap,
  });

  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_rounded),
            color: AppTheme.amber,
            tooltip: 'Remove from wishlist',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _WishlistSkeleton extends StatelessWidget {
  const _WishlistSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: AppSpacing.page,
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 110, height: 22),
            SizedBox(height: 16),
            SkeletonBox(height: 76, radius: 24),
            SizedBox(height: 12),
            SkeletonBox(height: 76, radius: 24),
            SizedBox(height: 12),
            SkeletonBox(height: 76, radius: 24),
          ],
        ),
      ),
    );
  }
}
