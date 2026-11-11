import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../data/social_repository.dart';
import '../domain/live_location.dart';
import '../../map/cached_tile_provider.dart';

final _groupLiveProvider = FutureProvider.autoDispose
    .family<List<LiveLocation>, String>(
      (ref, adventureId) => ref
          .watch(socialRepositoryProvider)
          .getGroupLiveLocations(adventureId),
    );

class GroupLiveMapScreen extends ConsumerWidget {
  const GroupLiveMapScreen({
    super.key,
    required this.adventureId,
    required this.adventureName,
  });

  final String adventureId;
  final String adventureName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveAsync = ref.watch(_groupLiveProvider(adventureId));

    return Scaffold(
      appBar: AppBar(
        title: Text('$adventureName — Live'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(_groupLiveProvider(adventureId)),
          ),
        ],
      ),
      body: liveAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(child: SkeletonBox(height: 320, radius: 28)),
        ),
        error: (error, stack) => Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load live locations',
            message: '$error',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(_groupLiveProvider(adventureId)),
          ),
        ),
        data: (locations) {
          if (locations.isEmpty) {
            return const Padding(
              padding: AppSpacing.page,
              child: EmptyStateCard(
                icon: Icons.location_off_outlined,
                title: 'Nobody is live right now',
                message:
                    'Nobody in this group is sharing their live location right now. '
                    'Start tracking and turn on "Share live location with friends" to show up here.',
              ),
            );
          }

          final points = locations
              .map((l) => LatLng(l.latitude, l.longitude))
              .toList();
          final bounds = points.length > 1
              ? LatLngBounds.fromPoints(points)
              : LatLngBounds(points.first, points.first);

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(48),
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.real_world_exploration',
                      tileProvider: CachedTileProvider(),
                    ),
                    MarkerLayer(
                      markers: [
                        for (final location in locations)
                          Marker(
                            point: LatLng(
                              location.latitude,
                              location.longitude,
                            ),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.forest,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.forest.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.navigation,
                                color: AppTheme.amber,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  children: [
                    for (final location in locations)
                      SoftCard(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        radius: 22,
                        child: Row(
                          children: [
                            AppAvatar(initial: location.displayName, size: 38),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  location.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                Text(
                                  _relativeTime(location.updatedAt),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    return '${difference.inHours}h ago';
  }
}
