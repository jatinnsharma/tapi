import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../../auth/application/display_name_provider.dart';
import '../../map/osm_tiles.dart';
import '../../planner/data/saved_trips_repository.dart';
import '../data/tour_repository.dart';
import '../domain/curated_tour.dart';

/// A community tour: its stops on a map, ratings, and "Plan this tour".
class TourDetailScreen extends ConsumerWidget {
  const TourDetailScreen({super.key, required this.tour});

  final CuratedTour tour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).value?.uid;
    final isMine = uid == tour.creatorUid;
    final ratingsAsync = ref.watch(tourRatingsProvider(tour.id));
    final ratings = ratingsAsync.value ?? const <TourRating>[];
    final average = averageStars(ratings);
    final mine = ratings.where((r) => r.uid == uid).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tour.title),
        actions: [
          if (isMine)
            IconButton(
              tooltip: 'Delete tour',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            'By ${tour.creatorName} · ${tour.cityName} · '
            '${tour.stops.length} stops · '
            '${tour.stopToStopKm.toStringAsFixed(1)} km stop to stop',
            style: const TextStyle(color: AppTheme.inkMuted),
          ),
          if (average != null) ...[
            const SizedBox(height: 4),
            Text(
              '★ ${average.toStringAsFixed(1)} (${ratings.length} '
              '${ratings.length == 1 ? 'rating' : 'ratings'})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.amberText,
              ),
            ),
          ],
          if (tour.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tour.description, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([
                      for (final s in tour.stops) s.position,
                    ]),
                    padding: const EdgeInsets.all(32),
                    maxZoom: 16,
                  ),
                ),
                children: [
                  osmTileLayer(),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [for (final s in tour.stops) s.position],
                        strokeWidth: 3,
                        color: AppTheme.forest,
                        pattern: StrokePattern.dotted(),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final (i, s) in tour.stops.indexed)
                        Marker(
                          point: s.position,
                          width: 28,
                          height: 28,
                          child: CircleAvatar(
                            backgroundColor: AppTheme.forest,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const OsmAttribution(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final (i, stop) in tour.stops.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(stop.name),
              subtitle: stop.tip == null || stop.tip!.isEmpty
                  ? null
                  : Text(stop.tip!),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.event_available),
            label: const Text('Plan this tour'),
            onPressed: () => _plan(context, ref),
          ),
          if (!isMine && uid != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.star_outline),
              label: Text(mine == null ? 'Rate this tour' : 'Change my rating'),
              onPressed: () => _rate(context, ref, uid, mine),
            ),
          ],
          if (ratings.any((r) => r.review.isNotEmpty)) ...[
            const SectionHeader(
              title: 'Reviews',
              padding: EdgeInsets.only(top: 22, bottom: 8),
            ),
            for (final r in ratings.where((r) => r.review.isNotEmpty))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${'★' * r.stars} ${r.name}'),
                subtitle: Text(r.review),
              ),
          ],
        ],
      ),
    );
  }

  /// Copies the tour into My Trips as a one-day plan and opens it.
  Future<void> _plan(BuildContext context, WidgetRef ref) async {
    final saved = await ref
        .read(savedTripsListProvider.notifier)
        .save(tourAsTripPlan(tour, now: DateTime.now()));
    if (!context.mounted) return;
    context.push('/trips/${saved.id}');
  }

  Future<void> _rate(
    BuildContext context,
    WidgetRef ref,
    String uid,
    TourRating? current,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({int stars, String review})>(
      context: context,
      builder: (_) => _RateDialog(current: current),
    );
    if (result == null) return;
    try {
      await ref
          .read(tourRepositoryProvider)
          .rate(
            tour.id,
            TourRating(
              uid: uid,
              name: ref.read(displayNameProvider) ?? 'Explorer',
              stars: result.stars,
              review: result.review,
            ),
          );
      ref.invalidate(tourRatingsProvider(tour.id));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save your rating.')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this tour?'),
        content: const Text('Others will no longer see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tourRepositoryProvider).delete(tour.id);
      ref.invalidate(cityToursProvider(tour.cityId));
      navigator.pop();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete the tour.')),
      );
    }
  }
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({this.current});

  final TourRating? current;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late int _stars = widget.current?.stars ?? 0;
  late final _review = TextEditingController(text: widget.current?.review);

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rate this tour'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                  icon: Icon(
                    i <= _stars ? Icons.star_rounded : Icons.star_outline,
                    color: AppTheme.amber,
                  ),
                  onPressed: () => setState(() => _stars = i),
                ),
            ],
          ),
          TextField(
            controller: _review,
            maxLength: maxReviewLength,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Review (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _stars == 0
              ? null
              : () =>
                    Navigator.of(context)
                        .pop((stars: _stars, review: _review.text.trim())),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
