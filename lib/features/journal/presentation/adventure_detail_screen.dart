import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../memories/data/memory_repository.dart';
import '../../memories/domain/memory_model.dart';
import '../../memories/presentation/memory_widgets.dart';
import '../../tracking/data/adventure_repository.dart';
import '../../tracking/domain/adventure_session.dart';
import '../../tracking/presentation/journey_trek_breakdown.dart';
import '../../tracking/domain/checkpoint.dart';
import '../../tracking/domain/route_point.dart';
import '../../map/cached_tile_provider.dart';
import '../../map/person_marker.dart';

class AdventureJournalData {
  const AdventureJournalData({
    required this.session,
    required this.routePoints,
    required this.checkpoints,
    required this.memories,
  });

  final AdventureSession session;
  final List<RoutePoint> routePoints;
  final List<Checkpoint> checkpoints;
  final List<Memory> memories;
}

final adventureJournalProvider = FutureProvider.autoDispose
    .family<AdventureJournalData?, String>((ref, adventureId) async {
      final adventureRepository = ref.watch(adventureRepositoryProvider);
      final memoryRepository = ref.watch(memoryRepositoryProvider);

      final session = await adventureRepository.getAdventureById(adventureId);
      if (session == null) return null;

      final routePoints = await adventureRepository.getRoutePoints(adventureId);
      final checkpoints = await adventureRepository.getCheckpoints(adventureId);
      final memories = await memoryRepository.getByAdventure(adventureId);

      return AdventureJournalData(
        session: session,
        routePoints: routePoints,
        checkpoints: checkpoints,
        memories: memories,
      );
    });

class AdventureDetailScreen extends ConsumerWidget {
  const AdventureDetailScreen({super.key, required this.adventureId});

  final String adventureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journalAsync = ref.watch(adventureJournalProvider(adventureId));

    return Scaffold(
      appBar: AppBar(title: const Text('Adventure Journal')),
      body: journalAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 120, radius: 32),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 82, radius: 22)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonBox(height: 82, radius: 22)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonBox(height: 82, radius: 22)),
                  ],
                ),
                SizedBox(height: 24),
                SkeletonBox(height: 220, radius: 28),
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
              title: 'Could not load adventure',
              message: '$error',
              actionLabel: 'Try again',
              onAction: () =>
                  ref.invalidate(adventureJournalProvider(adventureId)),
            ),
          ),
        ),
        data: (data) {
          if (data == null) {
            return const Padding(
              padding: AppSpacing.page,
              child: Align(
                alignment: Alignment.topCenter,
                child: EmptyStateCard(
                  icon: Icons.menu_book_outlined,
                  title: 'Adventure not found',
                  message: 'This adventure could not be found.',
                ),
              ),
            );
          }
          return ListView(
            padding: AppSpacing.page,
            children: [
              FadeSlideIn(
                child: HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.session.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatFullDate(data.session.startedAt),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      MetaPill(
                        icon: Icons.bolt_rounded,
                        label: '+${data.session.xpEarned} XP',
                        background: AppTheme.amber,
                        foreground: AppTheme.ink,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: _StatsRow(session: data.session),
              ),
              const SizedBox(height: 16),
              if (data.routePoints.length >= 2) ...[
                _RouteMap(
                  routePoints: data.routePoints,
                  checkpoints: data.checkpoints,
                ),
                const SizedBox(height: 12),
              ],
              if (data.checkpoints.isNotEmpty) ...[
                const SectionHeader(title: 'Checkpoints'),
                for (final checkpoint in data.checkpoints)
                  SoftCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    radius: 20,
                    child: Row(
                      children: [
                        Icon(
                          checkpoint.isReached
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: checkpoint.isReached
                              ? AppTheme.emerald
                              : AppTheme.inkMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            checkpoint.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+${checkpoint.xpReward} XP',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.amberText,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'Memories',
                      padding: EdgeInsets.only(top: 8, bottom: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (data.memories.isEmpty)
                const EmptyStateCard(
                  icon: Icons.photo_camera_outlined,
                  title: 'No memories yet',
                  message:
                      'No photos or voice notes captured on this adventure.',
                )
              else
                MemoriesGrid(memories: data.memories),
            ],
          );
        },
      ),
    );
  }

  String _formatFullDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.session});

  final AdventureSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(child: JourneyTrekBreakdown.ofSession(session)),
        const SizedBox(height: 10),
        StatTile(value: '${session.xpEarned}', label: 'XP earned'),
      ],
    );
  }
}

class _RouteMap extends StatefulWidget {
  const _RouteMap({required this.routePoints, required this.checkpoints});

  final List<RoutePoint> routePoints;
  final List<Checkpoint> checkpoints;

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController)
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _isPlaying = false;
          });
        }
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleReplay() {
    if (_isPlaying) {
      _animationController.stop();
    } else {
      if (_animationController.isCompleted) {
        _animationController.reset();
      }
      _animationController.forward();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.routePoints.isEmpty) return const SizedBox.shrink();

    final points = widget.routePoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    final bounds = LatLngBounds.fromPoints(points);

    final currentIndex = (_animation.value * (points.length - 1)).floor();
    final visiblePoints = points.sublist(0, currentIndex + 1);
    final currentPoint = points[currentIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionHeader(
                title: 'Route Map',
                padding: EdgeInsets.only(top: 8, bottom: 8),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: _toggleReplay,
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(
                _isPlaying
                    ? 'Pause'
                    : (_animationController.value == 0
                          ? 'Replay Route'
                          : 'Resume'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.forest.withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: SizedBox(
              height: 220,
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(24),
                  ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.real_world_exploration',
                    tileProvider: CachedTileProvider(),
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        strokeWidth: 4,
                        color: AppTheme.emerald.withValues(alpha: 0.3),
                      ),
                      Polyline(
                        points: visiblePoints,
                        strokeWidth: 4,
                        color: AppTheme.emerald,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      startMarker(points.first),
                      if (_animation.value == 1.0)
                        Marker(
                          point: points.last,
                          width: 24,
                          height: 24,
                          child: const Icon(
                            Icons.flag_circle,
                            color: Colors.red,
                            size: 24,
                          ),
                        ),
                      for (final checkpoint in widget.checkpoints)
                        Marker(
                          point: LatLng(
                            checkpoint.latitude,
                            checkpoint.longitude,
                          ),
                          width: 24,
                          height: 24,
                          child: Icon(
                            Icons.circle,
                            size: 14,
                            color: checkpoint.isReached
                                ? Colors.green
                                : AppTheme.inkMuted,
                          ),
                        ),
                      if (_isPlaying || _animationController.value > 0)
                        personMarker(currentPoint),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
