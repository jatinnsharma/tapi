import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../map/osm_tiles.dart';
import '../application/heatmap_service.dart';
import 'poster_screen.dart';

/// Glow colour of the routes on the dark map.
const _glow = Color(0xFFFFB347);

/// `/heatmap`: every counted trip's route glowing on a dark map, and a way to
/// turn it into a poster.
class HeatmapScreen extends ConsumerWidget {
  const HeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final footprintAsync = ref.watch(explorationFootprintProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My exploration map')),
      body: footprintAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          padding: AppSpacing.page,
          children: const [
            EmptyStateCard(
              icon: Icons.error_outline,
              title: 'Could not load your routes',
              message: 'Please try again in a moment.',
            ),
          ],
        ),
        data: (footprint) {
          if (footprint.isEmpty) {
            return ListView(
              padding: AppSpacing.page,
              children: const [
                EmptyStateCard(
                  icon: Icons.route_outlined,
                  title: 'No routes yet',
                  message:
                      'Finish a trip that counts and its route lights up '
                      'here.',
                ),
              ],
            );
          }
          final everyPoint = [for (final r in footprint.routes) ...r];
          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(everyPoint),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 16,
                  ),
                ),
                children: [
                  osmTileLayer(tileBuilder: darkModeTileBuilder),
                  PolylineLayer(
                    polylines: [
                      // A wide faint stroke under a thin bright one: a glow.
                      for (final route in footprint.routes)
                        Polyline(
                          points: route,
                          strokeWidth: 9,
                          color: _glow.withValues(alpha: 0.22),
                        ),
                      for (final route in footprint.routes)
                        Polyline(points: route, strokeWidth: 2.5, color: _glow),
                    ],
                  ),
                  const OsmAttribution(),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 40,
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${footprint.trips} trips · '
                            '${footprint.trekKm.toStringAsFixed(1)} km on foot',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.amber,
                          foregroundColor: AppTheme.ink,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PosterScreen(footprint: footprint),
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Create poster'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
