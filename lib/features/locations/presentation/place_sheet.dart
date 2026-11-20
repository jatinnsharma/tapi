import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/app_components.dart';
import '../../tracking/application/tracking_service.dart';
import '../../tracking/data/adventure_repository.dart';
import '../../tracking/data/directions_service.dart';
import '../../tracking/domain/trip_split.dart';
import '../../tracking/presentation/journey_trek_breakdown.dart';
import '../../wishlist/presentation/wishlist_button.dart';
import '../domain/location.dart';
import 'place_photo_gallery.dart';
import 'location_tips_section.dart';
import '../../ar/presentation/ar_wayfinder_screen.dart';
import '../../lens/presentation/lens_screen.dart';

/// Opens the details of a place: photos, what it is, how to get there and
/// tips, with **Start trip** always in reach in a sticky bar at the bottom.
///
/// [undiscovered] is for places still under the Map's fog: no name, photos
/// or saving, just how far away it is and "Head that way".
Future<void> showPlaceSheet(
  BuildContext context, {
  required ExploreLocation place,
  double? distanceKm,
  bool undiscovered = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: undiscovered ? 0.55 : 0.7,
      minChildSize: 0.3,
      maxChildSize: 1,
      builder: (_, scrollController) => _PlaceSheet(
        place: place,
        distanceKm: distanceKm,
        undiscovered: undiscovered,
        scrollController: scrollController,
        parentContext: context,
      ),
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
/// Trips can start anywhere a location fix is available. The journey to a
/// far-away place counts as journey, not trek (see `trip_split.dart`).
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
    required this.undiscovered,
    required this.scrollController,
    required this.parentContext,
  });

  final ExploreLocation place;

  /// Straight-line distance from the user, when the caller knows it.
  final double? distanceKm;
  final bool undiscovered;
  final ScrollController scrollController;

  /// The screen that opened the sheet; used to navigate after it closes.
  final BuildContext parentContext;

  /// Shown in place of the name while a place is under the fog.
  static const unknownName = 'Unknown place';

  /// AR "Point me there" only helps when the place is close by.
  static const arMaxKm = 2.0;

  /// Rough walking time at 5 km/h, shown until real directions load.
  static String walkTime(double distanceKm) {
    final minutes = (distanceKm / 5 * 60).round();
    if (minutes < 60) return '~$minutes min walk';
    return '~${(minutes / 60).toStringAsFixed(1)} h walk';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final visitedIds =
        ref.watch(visitedPlaceIdsProvider).value ?? const <String>{};
    final isVisited = visitedIds.contains(place.id);
    final isMysteryHidden = !undiscovered && place.isHiddenMystery(visitedIds);

    final displayName = undiscovered ? unknownName : place.nameFor(visitedIds);
    // The name used for the trip: kept secret until you get there.
    final tripName = undiscovered
        ? unknownName
        : (isMysteryHidden ? ExploreLocation.mysteryName : null);
    final description = isMysteryHidden
        ? (place.mysteryHint ?? ExploreLocation.mysteryFallbackHint)
        : place.description;

    final distance = distanceKm;
    final metaLine = [
      if (distance != null) '${distance.toStringAsFixed(1)} km away',
      if (distance != null && !undiscovered) walkTime(distance),
    ].join(' · ');

    final startLabel = undiscovered
        ? 'Head that way'
        : (isMysteryHidden ? 'Start the hunt' : 'Start trip');

    final showAr =
        arSupported && !undiscovered && distance != null && distance <= arMaxKm;
    final canIdentify = arSupported && !undiscovered;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              if (undiscovered)
                _UnknownPhoto(color: colors.surfaceMuted)
              else if (isMysteryHidden)
                _HiddenPhoto(place: place)
              else
                PlacePhotoGallery(place: place, height: 210),
              const SizedBox(height: 16),
              Text(displayName, style: text.headlineSmall),
              const SizedBox(height: 8),
              if (!undiscovered)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Tag(
                      isMysteryHidden ? 'Mystery' : place.category.label,
                      icon: isMysteryHidden
                          ? Icons.help_outline_rounded
                          : place.category.icon,
                      tone: TagTone.brand,
                    ),
                    if (place.isMystery && isVisited)
                      const Tag(
                        'Mystery solved',
                        icon: Icons.check_circle_rounded,
                      )
                    else if (place.difficulty != null)
                      Tag(place.difficulty!, icon: Icons.terrain),
                  ],
                ),
              if (metaLine.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  metaLine,
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: 16),
              if (undiscovered)
                Text(
                  'Get closer to find out what this place is.',
                  style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                )
              else ...[
                if (isMysteryHidden) ...[
                  const StatusBanner(
                    kind: StatusKind.info,
                    title: 'A mystery place',
                    message: 'Follow the directions to find out what\'s hidden here.',
                  ),
                  const SizedBox(height: 12),
                ],
                _ExpandableText(description),
                const SizedBox(height: 24),
                TripPlanCard(
                  place: place,
                  straightLineKm: distanceKm,
                  displayName: displayName,
                ),
                if (!isMysteryHidden) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  LocationTipsSection(location: place),
                ],
              ],
            ],
          ),
        ),
        _ActionBar(
          startLabel: startLabel,
          xp: undiscovered ? null : place.xpReward,
          onStart: () {
            Navigator.of(context).pop();
            startTripToPlace(parentContext, ref, place, displayName: tripName);
          },
          save: undiscovered ? null : WishlistIconButton(place: place),
          moreItems: [
            if (showAr)
              (
                icon: Icons.view_in_ar_outlined,
                label: 'Point me there (AR)',
                onTap: () => showArWayfinder(
                  parentContext,
                  name: displayName,
                  target: LatLng(place.latitude, place.longitude),
                ),
              ),
            if (canIdentify)
              (
                icon: Icons.center_focus_strong_outlined,
                label: 'Identify what\'s here',
                onTap: () => showLens(parentContext, near: displayName),
              ),
          ],
        ),
      ],
    );
  }
}

/// Blurred photos of a mystery place, with a note on how to reveal them.
class _HiddenPhoto extends StatelessWidget {
  const _HiddenPhoto({required this.place});

  final ExploreLocation place;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ExcludeSemantics(
              child: PlacePhotoGallery(place: place, height: 210),
            ),
          ),
        ),
        const Tag(
          'Photo hidden until you get there',
          icon: Icons.lock_rounded,
          tone: TagTone.onImage,
        ),
      ],
    );
  }
}

/// A placeholder for a place still under the fog: no photo, no hints.
class _UnknownPhoto extends StatelessWidget {
  const _UnknownPhoto({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.help_outline_rounded,
        size: 48,
        color: AppColors.of(context).textSecondary,
        semanticLabel: 'Unknown place',
      ),
    );
  }
}

/// The first three lines, with "More" to read the rest.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  static const _collapsedLines = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: AppColors.of(context).textSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              AppButton.tertiary(
                label: _expanded ? 'Less' : 'More',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
          ],
        );
      },
    );
  }
}

typedef _MoreItem = ({IconData icon, String label, VoidCallback onTap});

/// Always visible at the bottom of the sheet: the XP on offer, the main
/// action, save, and any extra tools.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.startLabel,
    required this.onStart,
    required this.moreItems,
    this.xp,
    this.save,
  });

  final String startLabel;
  final VoidCallback onStart;
  final int? xp;
  final Widget? save;
  final List<_MoreItem> moreItems;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (xp != null) ...[
                Text(
                  '+$xp XP when you get there',
                  style: text.labelMedium?.copyWith(color: colors.rewardText),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: startLabel,
                      icon: Icons.play_arrow_rounded,
                      expand: true,
                      onPressed: onStart,
                    ),
                  ),
                  if (save != null) ...[const SizedBox(width: 4), save!],
                  if (moreItems.isNotEmpty)
                    PopupMenuButton<VoidCallback>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (action) => action(),
                      itemBuilder: (_) => [
                        for (final item in moreItems)
                          PopupMenuItem(
                            value: item.onTap,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(item.icon),
                              title: Text(item.label),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Before starting: how long the journey to the place takes (by car and on
/// foot, from real routes), and where the trek begins. Journey figures are for
/// planning only; trek statistics count only time on foot from the start.
class TripPlanCard extends ConsumerWidget {
  const TripPlanCard({
    super.key,
    required this.place,
    this.straightLineKm,
    this.displayName,
  });

  final ExploreLocation place;
  final double? straightLineKm;

  /// Overrides the shown name, e.g. to keep an unsolved mystery secret.
  final String? displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimate = ref.watch(
      journeyEstimateProvider((lat: place.latitude, lng: place.longitude)),
    );
    final value = estimate.value;
    final loading = estimate.isLoading && value == null;

    final text = Theme.of(context).textTheme;
    final name = displayName ?? place.name;
    return Column(
      key: const ValueKey('trip-plan'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Getting there', style: text.titleMedium)),
            AppIconButton(
              icon: Icons.info_outline_rounded,
              tooltip: 'How trips are counted',
              onPressed: () => showTripRulesSheet(context, placeName: name),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
      ],
    );
  }
}

/// Explains, once and out of the way, how a trip is split into the journey
/// (any transport, for planning) and the trek (on foot, for stats).
Future<void> showTripRulesSheet(
  BuildContext context, {
  required String placeName,
}) {
  final style = Theme.of(context).textTheme.bodyLarge;
  return showAppSheet<void>(
    context,
    title: 'How trips are counted',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your trek starts within '
          '${TripSplit.trekStartRadiusMeters.round()} m of $placeName. '
          'Only your time on foot from there counts for trek stats and '
          'achievements.',
          style: style,
        ),
        const SizedBox(height: 12),
        Text(
          'Getting there by car, bus or on foot is your journey. It\'s shown '
          'to help you plan, and you can start from anywhere.',
          style: style,
        ),
      ],
    ),
  );
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
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final brand = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: brand),
              const SizedBox(width: 6),
              Text(title, style: text.labelLarge?.copyWith(color: brand)),
            ],
          ),
          const SizedBox(height: 6),
          if (value case final v?) Text(v, style: text.titleMedium),
          Text(
            detail,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
