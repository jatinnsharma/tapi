import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../data/memory_repository.dart';
import 'memory_capture.dart';
import 'memory_widgets.dart';

final allMemoriesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(memoryRepositoryProvider).getAll(limit: 200);
});

class MemoriesGalleryScreen extends ConsumerWidget {
  const MemoriesGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoriesAsync = ref.watch(allMemoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Calendar',
            onPressed: () => context.push('/calendar'),
          ),
          IconButton(
            icon: const Icon(Icons.groups_2_outlined),
            tooltip: 'Community memories',
            onPressed: () => context.push('/community-memories'),
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: 'Add a memory',
            onPressed: () async {
              final saved = await showAddMemorySheet(context);
              if (saved > 0) ref.invalidate(allMemoriesProvider);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: memoriesAsync.when(
        loading: () => Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 9; i++) const SkeletonBox(radius: 18),
              ],
            ),
          ),
        ),
        error: (error, stack) => Padding(
          padding: AppSpacing.page,
          child: Align(
            alignment: Alignment.topCenter,
            child: EmptyStateCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load memories',
              message: '$error',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(allMemoriesProvider),
            ),
          ),
        ),
        data: (memories) {
          if (memories.isEmpty) {
            return const Padding(
              padding: AppSpacing.page,
              child: Align(
                alignment: Alignment.topCenter,
                child: EmptyStateCard(
                  icon: Icons.photo_library_outlined,
                  title: 'No memories yet',
                  message:
                      'Capture a photo or voice note on your next adventure!',
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: AppTheme.forest,
            onRefresh: () async => ref.invalidate(allMemoriesProvider),
            child: ListView(
              padding: AppSpacing.page,
              children: [
                MemoriesGrid(
                  memories: memories,
                  onChanged: () => ref.invalidate(allMemoriesProvider),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
