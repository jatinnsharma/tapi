import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../auth/application/auth_service.dart';
import '../data/shared_memory_service.dart';
import '../domain/shared_memory.dart';
import 'memory_viewer.dart';

/// Photos and videos other explorers have shared: what your friends shared
/// with you, or everything shared publicly.
class CommunityMemoriesScreen extends ConsumerStatefulWidget {
  const CommunityMemoriesScreen({super.key});

  @override
  ConsumerState<CommunityMemoriesScreen> createState() =>
      _CommunityMemoriesScreenState();
}

class _CommunityMemoriesScreenState
    extends ConsumerState<CommunityMemoriesScreen> {
  bool _friendsOnly = true;

  @override
  Widget build(BuildContext context) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = firebaseReady ? ref.watch(authStateProvider).value : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Community memories')),
      body: !firebaseReady || user == null
          ? Padding(
              padding: AppSpacing.page,
              child: Align(
                alignment: Alignment.topCenter,
                child: EmptyStateCard(
                  icon: Icons.photo_library_outlined,
                  title: 'Sign in to watch memories',
                  message: 'See the photos and videos your friends and other explorers share.',
                  actionLabel: firebaseReady ? 'Sign In' : null,
                  onAction: firebaseReady ? () => context.push('/login') : null,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppTheme.forest,
                        selectedForegroundColor: Colors.white,
                        foregroundColor: AppTheme.ink,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.group_outlined, size: 18),
                          label: Text('Friends'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.public, size: 18),
                          label: Text('Everyone'),
                        ),
                      ],
                      selected: {_friendsOnly},
                      onSelectionChanged: (s) =>
                          setState(() => _friendsOnly = s.first),
                    ),
                  ),
                ),
                Expanded(child: _Feed(friendsOnly: _friendsOnly)),
              ],
            ),
    );
  }
}

class _Feed extends ConsumerWidget {
  const _Feed({required this.friendsOnly});

  final bool friendsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(communityMemoriesProvider(friendsOnly));

    return feedAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Shimmer(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 6; i++) const SkeletonBox(radius: 22),
            ],
          ),
        ),
      ),
      error: (error, _) => ListView(
        padding: AppSpacing.page,
        children: [
          EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load memories',
            message: '$error',
            actionLabel: 'Try again',
            onAction: () =>
                ref.invalidate(communityMemoriesProvider(friendsOnly)),
          ),
        ],
      ),
      data: (memories) {
        if (memories.isEmpty) {
          return ListView(
            padding: AppSpacing.page,
            children: [
              EmptyStateCard(
                icon: Icons.photo_library_outlined,
                title: friendsOnly
                    ? 'Nothing from your friends yet'
                    : 'Nothing shared yet',
                message: friendsOnly
                    ? 'When friends share a photo or video from a trip, it shows up here. You can share yours from your Memories.'
                    : 'Public photos and videos from explorers will show up here.',
              ),
            ],
          );
        }
        return RefreshIndicator(
          color: AppTheme.forest,
          onRefresh: () async =>
              ref.invalidate(communityMemoriesProvider(friendsOnly)),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: memories.length,
            itemBuilder: (context, i) => _Tile(memory: memories[i]),
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.memory});

  final SharedMemory memory;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SharedMemoryViewerScreen(memory: memory),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.forest.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (memory.isVideo)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.forest, Color(0xFF17694B)],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                  )
                else
                  Image.network(
                    memory.url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const Shimmer(
                            child: SkeletonBox(
                              height: double.infinity,
                              radius: 0,
                            ),
                          ),
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFFE0E7E2),
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                // Author and caption, readable on any photo.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC000000)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          memory.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        if (memory.caption != null &&
                            memory.caption!.isNotEmpty)
                          Text(
                            memory.caption!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
