import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../auth/application/auth_service.dart';
import '../../profile/domain/explorer_level.dart';
import '../application/leaderboard_service.dart';
import '../domain/leaderboard.dart';

/// Global and friends rankings by total XP.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  RankingScope _scope = RankingScope.global;
  RankingTimeframe _timeframe = RankingTimeframe.thisWeek;

  @override
  Widget build(BuildContext context) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = firebaseReady ? ref.watch(authStateProvider).value : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: !firebaseReady || user == null
          ? Padding(
              padding: AppSpacing.page,
              child: Align(
                alignment: Alignment.topCenter,
                child: EmptyStateCard(
                  icon: Icons.emoji_events_outlined,
                  title: 'Sign in to see the rankings',
                  message: 'Rankings compare your XP with other explorers and your friends.',
                  actionLabel: firebaseReady ? 'Sign In' : null,
                  onAction: firebaseReady ? () => context.push('/login') : null,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<RankingTimeframe>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppTheme.amber,
                        selectedForegroundColor: AppTheme.ink,
                        foregroundColor: AppTheme.ink,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: RankingTimeframe.thisWeek,
                          icon: Icon(Icons.bolt_rounded, size: 18),
                          label: Text('This Week'),
                        ),
                        ButtonSegment(
                          value: RankingTimeframe.allTime,
                          icon: Icon(
                            Icons.workspace_premium_outlined,
                            size: 18,
                          ),
                          label: Text('All-Time'),
                        ),
                      ],
                      selected: {_timeframe},
                      onSelectionChanged: (s) =>
                          setState(() => _timeframe = s.first),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<RankingScope>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppTheme.forest,
                        selectedForegroundColor: Colors.white,
                        foregroundColor: AppTheme.ink,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: RankingScope.global,
                          icon: Icon(Icons.public, size: 18),
                          label: Text('Global'),
                        ),
                        ButtonSegment(
                          value: RankingScope.friends,
                          icon: Icon(Icons.group_outlined, size: 18),
                          label: Text('Friends'),
                        ),
                      ],
                      selected: {_scope},
                      onSelectionChanged: (s) =>
                          setState(() => _scope = s.first),
                    ),
                  ),
                ),
                Expanded(
                  child: _Ranking(
                    filter: LeaderboardFilter(
                      scope: _scope,
                      timeframe: _timeframe,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Ranking extends ConsumerWidget {
  const _Ranking({required this.filter});

  final LeaderboardFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(leaderboardProvider(filter));

    return boardAsync.when(
      loading: () => const _RankingSkeleton(),
      error: (error, _) => ListView(
        padding: AppSpacing.page,
        children: [
          EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load the rankings',
            message: '$error',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(leaderboardProvider(filter)),
          ),
        ],
      ),
      data: (board) {
        final entries = board.entries;
        if (filter.scope == RankingScope.friends && entries.length <= 1) {
          return ListView(
            padding: AppSpacing.page,
            children: [
              EmptyStateCard(
                icon: Icons.group_add_outlined,
                title: 'No friends to compare with yet',
                message: 'Add friends from the Social tab to see how you rank among them.',
                actionLabel: 'Find explorers',
                onAction: () => context.go('/social'),
              ),
            ],
          );
        }
        if (entries.isEmpty) {
          return ListView(
            padding: AppSpacing.page,
            children: [
              EmptyStateCard(
                icon: Icons.emoji_events_outlined,
                title: filter.timeframe == RankingTimeframe.thisWeek
                    ? 'No weekly activity yet'
                    : 'No rankings yet',
                message: 'Finish an adventure to earn XP and appear here.',
              ),
            ],
          );
        }

        final podium = entries.take(3).toList();
        final rest = entries.skip(3).toList();
        final me = board.me;

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.forest,
                onRefresh: () async =>
                    ref.invalidate(leaderboardProvider(filter)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (filter.timeframe == RankingTimeframe.thisWeek)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: Text(
                            'Resets every Monday · Fresh start for everyone',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    FadeSlideIn(child: _Podium(entries: podium)),
                    const SizedBox(height: 18),
                    for (final entry in rest)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RankRow(entry: entry),
                      ),
                    if (filter.scope == RankingScope.global &&
                        entries.length >= globalLeaderboardSize)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Center(
                          child: Text(
                            'Showing the top $globalLeaderboardSize explorers',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.inkMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Always show where you stand, even outside the listed rows.
            if (me != null && !board.meIsListed)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: _RankRow(entry: me, pinned: true),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The top three: first in the middle and tallest.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final first = entries.isNotEmpty ? entries[0] : null;
    final second = entries.length > 1 ? entries[1] : null;
    final third = entries.length > 2 ? entries[2] : null;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _PodiumSpot(entry: second, height: 58)),
          Expanded(child: _PodiumSpot(entry: first, height: 82)),
          Expanded(child: _PodiumSpot(entry: third, height: 44)),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({required this.entry, required this.height});

  final LeaderboardEntry? entry;
  final double height;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return const SizedBox.shrink();
    final medal = switch (e.rank) {
      1 => const Color(0xFFF5C542),
      2 => const Color(0xFFCFD8DC),
      _ => const Color(0xFFD7A26A),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: medal),
              child: AppAvatar(
                initial: e.displayName,
                size: e.rank == 1 ? 60 : 50,
              ),
            ),
            Positioned(
              bottom: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: medal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '#${e.rank}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          e.isMe ? 'You' : e.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        Text(
          '${_formatXp(e.totalXp)} XP',
          style: const TextStyle(
            color: AppTheme.amber,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: e.rank == 1 ? 0.24 : 0.14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
        ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, this.pinned = false});

  final LeaderboardEntry entry;

  /// Shown below the list: "your position" rather than a list row.
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final level = ExplorerLevel.levelNumberForXp(entry.totalXp);
    final title = ExplorerLevel.forXp(entry.totalXp).title;
    final highlight = entry.isMe;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.emerald.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? AppTheme.emerald : Colors.white,
          width: highlight ? 1.6 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.forest.withValues(alpha: pinned ? 0.18 : 0.08),
            blurRadius: pinned ? 20 : 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#${entry.rank}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          AppAvatar(initial: entry.displayName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isMe ? '${entry.displayName} (you)' : entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  'Level $level · $title',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${_formatXp(entry.totalXp)} XP',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.amberText,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingSkeleton extends StatelessWidget {
  const _RankingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Shimmer(
        child: Column(
          children: [
            SkeletonBox(height: 190, radius: 32),
            SizedBox(height: 18),
            SkeletonBox(height: 64, radius: 20),
            SizedBox(height: 10),
            SkeletonBox(height: 64, radius: 20),
            SizedBox(height: 10),
            SkeletonBox(height: 64, radius: 20),
          ],
        ),
      ),
    );
  }
}

/// 2450 → "2,450".
String _formatXp(int xp) {
  final digits = xp.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
