import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../tracking/application/tracking_service.dart';
import '../../tracking/data/adventure_repository.dart';
import '../../tracking/data/directions_service.dart';
import '../../tracking/domain/trip_split.dart';
import '../../tracking/presentation/journey_trek_breakdown.dart';
import '../domain/location.dart';
import 'place_photo_gallery.dart';

/// Opens the details of a place with a one-tap **Start** that begins a
/// tracked adventure to it, with live step-by-step directions.
Future<void> showPlaceSheet(
  BuildContext context, {
  required ExploreLocation place,
  double? distanceKm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _PlaceSheet(
      place: place,
      distanceKm: distanceKm,
      parentContext: context,
    ),
  );
}

/// Starts a tracked adventure to [place] with step-by-step directions. Shared
/// by every "Start" on a place (Home, Map, Wishlist, ...). [context] must be
/// a screen's context, not a sheet's that is about to close.
///
/// [displayName] overrides the shown name, e.g. to keep an undiscovered
/// place's name hidden.
///
/// Version 1 starts trips only inside the service area (Chandigarh): from
/// anywhere else the walking route could be hundreds of kilometres.
Future<void> startTripToPlace(
  BuildContext context,
  WidgetRef ref,
  ExploreLocation place, {
  String? displayName,
}) async {
  void tell(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  if (ref.read(trackingServiceProvider).hasSession) {
    // One adventure at a time: send them to the one in progress.
    tell(
      'You already have an adventure in progress. Finish or discard it first.',
    );
    context.push('/tracking');
    return;
  }

  // Read before the await: the caller (often a sheet) may be gone after it.
  final locationService = ref.read(locationServiceProvider);
  // A recent position is enough to check the service area, and is instant.
  final here = await locationService.getCurrentLocation(acceptRecent: true);
  if (!context.mounted) return;
  if (here == null) {
    tell('Turn on location to start a trip.');
    return;
  }

  final name = displayName ?? place.name;
  context.push(
    Uri(
      path: '/tracking',
      queryParameters: {
        'title': name,
        'destId': place.id,
        'destName': name,
        'destLat': '${place.latitude}',
        'destLng': '${place.longitude}',
        'destXp': '${place.xpReward}',
        'autostart': '1',
      },
    ).toString(),
  );
}

class _PlaceSheet extends ConsumerWidget {
  const _PlaceSheet({
    required this.place,
    required this.distanceKm,
    required this.parentContext,
  });

  final ExploreLocation place;

  /// Straight-line distance from the user, when the caller knows it.
  final double? distanceKm;

  /// The screen that opened the sheet; used to navigate after it closes.
  final BuildContext parentContext;

  /// Rough walking time at 5 km/h, shown until real directions load.
  String _walkTime(double distanceKm) {
    final minutes = (distanceKm / 5 * 60).round();
    if (minutes < 60) return '~$minutes min walk';
    return '~${(minutes / 60).toStringAsFixed(1)} h walk';
  }

  void _start(
    BuildContext sheetContext,
    WidgetRef ref, {
    required bool isMysteryHidden,
  }) {
    Navigator.of(sheetContext).pop();
    startTripToPlace(
      parentContext,
      ref,
      place,
      displayName: isMysteryHidden ? 'Mystery Place' : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitedIds =
        ref.watch(visitedPlaceIdsProvider).value ?? const <String>{};
    final isVisited = visitedIds.contains(place.id);
    final isMysteryHidden = place.isMystery && !isVisited;

    final displayName = isMysteryHidden ? 'Mystery Place' : place.name;
    final displayDescription = isMysteryHidden
        ? (place.mysteryHint ??
              'A secret hidden location. Walk here on foot to solve the mystery!')
        : place.description;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Swipe through real photos of the place; blurred if mystery and not yet visited.
          if (isMysteryHidden)
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: PlacePhotoGallery(place: place, height: 210),
                  ),
                ),
                Container(
                  height: 210,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Photo Blurred · Walk Here to Unmask',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            PlacePhotoGallery(place: place, height: 210),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MetaPill(
                icon: isMysteryHidden
                    ? Icons.help_outline_rounded
                    : place.category.icon,
                label: isMysteryHidden ? 'Mystery' : place.category.label,
                background: isMysteryHidden
                    ? Colors.deepPurple
                    : AppTheme.forest,
              ),
              if (distanceKm != null)
                MetaPill(
                  icon: Icons.near_me_outlined,
                  label:
                      '${distanceKm!.toStringAsFixed(1)} km · ${_walkTime(distanceKm!)}',
                  background: AppTheme.primaryGreen,
                ),
              MetaPill(
                icon: Icons.bolt_rounded,
                label: '+${place.xpReward} XP',
                background: AppTheme.amber,
                foreground: AppTheme.ink,
              ),
              if (place.isMystery && isVisited)
                const MetaPill(
                  icon: Icons.check_circle_rounded,
                  label: 'Mystery Solved',
                  background: Colors.deepPurple,
                ),
              if (place.difficulty != null)
                MetaPill(
                  icon: Icons.terrain,
                  label: place.difficulty!,
                  background: AppTheme.inkMuted,
                ),
            ],
          ),
          if (isMysteryHidden) ...[
            const SizedBox(height: 14),
            GlassCard(
              tint: Colors.deepPurple,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.psychology_alt_rounded,
                      color: Colors.deepPurple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mystery Location Challenge',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppTheme.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Follow the directions and explore on foot to discover what place is hidden here.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          TripPlanCard(place: place, straightLineKm: distanceKm),
          const SizedBox(height: 14),
          Text(
            displayDescription,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: AppTheme.inkMuted,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  _start(context, ref, isMysteryHidden: isMysteryHidden),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(isMysteryHidden ? 'Hunt This Mystery' : 'Start'),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Tracks your route and guides you there step by step.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Before starting: how long the journey to the place takes (by car and on
/// foot, from real routes), and where the trek begins. Journey figures are for
/// planning only; trek statistics count only time on foot from the start.
class TripPlanCard extends ConsumerWidget {
  const TripPlanCard({super.key, required this.place, this.straightLineKm});

  final ExploreLocation place;
  final double? straightLineKm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimate = ref.watch(
      journeyEstimateProvider((lat: place.latitude, lng: place.longitude)),
    );
    final value = estimate.value;
    final loading = estimate.isLoading && value == null;

    return SoftCard(
      key: const ValueKey('trip-plan'),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded, color: AppTheme.forest, size: 20),
              SizedBox(width: 8),
              Text(
                'Plan your trip',
                style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Journey: getting there by any transport',
            style: TextStyle(color: AppTheme.inkMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          if (loading)
            const Row(
              children: [
                Expanded(child: SkeletonBox(height: 74, radius: 18)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 74, radius: 18)),
              ],
            )
          else if (value == null || value.isEmpty)
            _ModeTile(
              icon: Icons.near_me_rounded,
              title: 'Straight line',
              detail: straightLineKm == null
                  ? 'Journey estimate unavailable right now.'
                  : 'About ${straightLineKm!.toStringAsFixed(1)} km away '
                        'in a straight line.',
            )
          else
            Row(
              children: [
                if (value.byCar case final car?)
                  Expanded(
                    child: _ModeTile(
                      icon: Icons.directions_car_filled_rounded,
                      title: 'By car',
                      value: formatTripDistance(car.meters),
                      detail: '~${formatTripDuration(car.duration)}',
                    ),
                  ),
                if (value.byCar != null && value.onFoot != null)
                  const SizedBox(width: 10),
                if (value.onFoot case final foot?)
                  Expanded(
                    child: _ModeTile(
                      icon: Icons.directions_walk_rounded,
                      title: 'On foot',
                      value: formatTripDistance(foot.meters),
                      detail: '~${formatTripDuration(foot.duration)}',
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.emerald.withValues(alpha: 0.16),
                  AppTheme.emerald.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.emerald.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppTheme.emerald,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hiking_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Trek starts within '
                    '${TripSplit.trekStartRadiusMeters.round()} m of '
                    '${place.name}. Only your time on foot from there counts '
                    'as trek, for stats and achievements.',
                    style: const TextStyle(
                      color: AppTheme.ink,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.detail,
    this.value,
  });

  final IconData icon;
  final String title;

  /// The headline figure, e.g. "5.30 km".
  final String? value;

  /// The line under it, e.g. "~14 min".
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.forest.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.forest.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.forest),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.forest,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (value case final v?)
            Text(
              v,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
