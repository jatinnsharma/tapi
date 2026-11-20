import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/components.dart';
import '../data/memory_repository.dart';
import '../domain/memory_model.dart';
import 'memory_capture.dart';
import 'memory_widgets.dart';

final allMemoriesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(memoryRepositoryProvider).getAll(limit: 200);
});

enum _Filter { all, media, voice }

class MemoriesGalleryScreen extends ConsumerStatefulWidget {
  const MemoriesGalleryScreen({super.key});

  @override
  ConsumerState<MemoriesGalleryScreen> createState() =>
      _MemoriesGalleryScreenState();
}

class _MemoriesGalleryScreenState extends ConsumerState<MemoriesGalleryScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _add() async {
    final saved = await showAddMemorySheet(context);
    if (saved > 0) ref.invalidate(allMemoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final memoriesAsync = ref.watch(allMemoriesProvider);
    final hasMemories = memoriesAsync.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          AppIconButton(
            icon: Icons.calendar_month_outlined,
            tooltip: 'Calendar',
            onPressed: () => context.push('/calendar'),
          ),
          AppIconButton(
            icon: Icons.groups_2_outlined,
            tooltip: 'Shared by others',
            onPressed: () => context.push('/community-memories'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // Adding is the main action: always one labelled button.
      floatingActionButton: hasMemories
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add memory'),
            )
          : null,
      body: memoriesAsync.when(
        loading: () => Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 9; i++)
                  const SkeletonBox(radius: AppRadius.sm),
              ],
            ),
          ),
        ),
        error: (error, stack) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(allMemoriesProvider),
        ),
        data: (memories) {
          if (memories.isEmpty) {
            return GateCard(
              icon: Icons.photo_library_outlined,
              title: 'No memories yet',
              message:
                  'Photos, videos and voice notes from your trips are kept '
                  'here, on this phone.',
              actionLabel: 'Add memory',
              onAction: _add,
            );
          }
          final hasVoice = memories.any((m) => m.type == MemoryType.voiceNote);
          final hasMedia = memories.any((m) => m.type != MemoryType.voiceNote);
          final shown = switch (_filter) {
            _Filter.all => memories,
            _Filter.media =>
              memories.where((m) => m.type != MemoryType.voiceNote).toList(),
            _Filter.voice =>
              memories.where((m) => m.type == MemoryType.voiceNote).toList(),
          };
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allMemoriesProvider),
            child: ListView(
              // Room for the Add button floating over the list.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                if (hasVoice && hasMedia) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (f, label) in const [
                        (_Filter.all, 'All'),
                        (_Filter.media, 'Photos & videos'),
                        (_Filter.voice, 'Voice notes'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                MemoriesGrid(
                  memories: shown,
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
