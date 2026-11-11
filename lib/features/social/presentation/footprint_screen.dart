import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../locations/domain/location.dart';
import '../../map/cached_tile_provider.dart';
import '../application/footprint_service.dart';
import '../domain/footprint.dart';

/// Another explorer's exploration footprint: every route they've completed
/// and every place they've visited, on one map. Only shows what their
/// visibility setting allows; otherwise explains that it isn't shared.
class FootprintScreen extends ConsumerWidget {
  const FootprintScreen({super.key, required this.uid, required this.name});

  final String uid;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(footprintOfProvider(uid));

    return Scaffold(
      appBar: AppBar(title: Text("$name's map")),
      body: resultAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Shimmer(child: SkeletonBox(height: 420, radius: 28)),
        ),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load this map',
            message: '$error',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(footprintOfProvider(uid)),
          ),
        ),
        data: (result) {
          final footprint = result.footprint;
          if (result.access == FootprintAccess.notShared || footprint == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: EmptyStateCard(
                icon: Icons.lock_outline_rounded,
                title: '$name keeps their map private',
                message: 'Their routes and visited places are only visible if they choose to share them.',
              ),
            );
          }
          return _FootprintMap(footprint: footprint);
        },
      ),
    );
  }
}

class _FootprintMap extends StatelessWidget {
  const _FootprintMap({required this.footprint});

  final Footprint footprint;

  @override
  Widget build(BuildContext context) {
    final routes = footprint.decodedRoutes;
    final places = footprint.places;
    final allPoints = [
      for (final route in routes) ...route,
      for (final p in places) p.point,
    ];

    if (allPoints.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: EmptyStateCard(
          icon: Icons.hiking_outlined,
          title: 'Nothing on this map yet',
          message:
              '${footprint.displayName} hasn\'t completed an adventure or visited a place yet.',
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: allPoints.length == 1
                ? null
                : CameraFit.coordinates(
                    coordinates: allPoints,
                    padding: const EdgeInsets.all(48),
                    maxZoom: 16,
                  ),
            initialCenter: allPoints.first,
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.real_world_exploration',
              tileProvider: CachedTileProvider(),
            ),
            PolylineLayer(
              polylines: [
                for (final route in routes)
                  Polyline(
                    points: route,
                    color: AppTheme.emerald.withValues(alpha: 0.7),
                    strokeWidth: 4,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final place in places)
                  Marker(
                    point: place.point,
                    width: 40,
                    height: 40,
                    child: Tooltip(
                      message: place.name,
                      child: _VisitedMarker(category: place.category),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: '${routes.length}',
                    label: routes.length == 1 ? 'Route' : 'Routes',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    value: '${places.length}',
                    label: places.length == 1
                        ? 'Place visited'
                        : 'Places visited',
                  ),
                ),
                MetaPill(
                  label: footprint.visibility.label,
                  icon: footprint.visibility == FootprintVisibility.public
                      ? Icons.public
                      : Icons.group_outlined,
                  background: AppTheme.forest,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
        ),
      ],
    );
  }
}

/// Visited places get the same gold-badged marker as on the personal map.
class _VisitedMarker extends StatelessWidget {
  const _VisitedMarker({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final cat = LocationCategory.values.firstWhere(
      (c) => c.name == category,
      orElse: () => LocationCategory.nature,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(cat.icon, color: cat.color, size: 30),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.amber,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
            ),
            padding: const EdgeInsets.all(2),
            child: const Icon(Icons.check, size: 10, color: AppTheme.ink),
          ),
        ),
      ],
    );
  }
}
