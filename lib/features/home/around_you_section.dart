import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../explore/presentation/widgets/city_picker_modal.dart';
import '../locations/data/place_photos_service.dart';
import '../locations/domain/location.dart';
import '../locations/presentation/place_sheet.dart';
import '../locations/presentation/place_style.dart';
import '../planner/data/opening_hours_service.dart';
import '../planner/domain/opening_hours.dart';
import '../tracking/data/adventure_repository.dart';

/// Kinds of place to filter "Around you" by.
enum AroundFilter {
  all('All', Icons.apps_rounded),
  heritage('Temples & heritage', Icons.account_balance_outlined),
  nature('Nature', Icons.park_outlined),
  food('Food', Icons.restaurant_outlined),
  photo('Photo spots', Icons.photo_camera_outlined),
  gems('Hidden gems', Icons.diamond_outlined);

  const AroundFilter(this.label, this.icon);
  final String label;
  final IconData icon;

  bool matches(LocationCategory c) => switch (this) {
    AroundFilter.all => true,
    AroundFilter.heritage => c == LocationCategory.heritage,
    AroundFilter.nature => const {
      LocationCategory.nature,
      LocationCategory.lake,
      LocationCategory.waterfall,
      LocationCategory.mountain,
      LocationCategory.trek,
      LocationCategory.camping,
    }.contains(c),
    AroundFilter.food => c == LocationCategory.food,
    AroundFilter.photo =>
      c == LocationCategory.photography || c == LocationCategory.viewpoint,
    AroundFilter.gems =>
      c == LocationCategory.hiddenGem || c == LocationCategory.mystery,
  };
}

/// One row of places around the user (or the chosen city), nearest first,
/// with chips to narrow it down and a distance limit. Replaces the separate
/// "near you", hidden gems, photo spots and popular rows.
class AroundYouSection extends ConsumerStatefulWidget {
  const AroundYouSection({
    super.key,
    required this.current,
    required this.hasLocation,
    required this.places,
    required this.loading,
    required this.fetchFailed,
    required this.onFindNearby,
    required this.onTurnOnLocation,
    this.selectedCityName,
  });

  final LatLng? current;
  final bool hasLocation;

  /// Every known place, nearest first.
  final List<ExploreLocation> places;
  final bool loading;
  final bool fetchFailed;
  final VoidCallback onFindNearby;
  final VoidCallback onTurnOnLocation;
  final String? selectedCityName;

  @override
  ConsumerState<AroundYouSection> createState() => _AroundYouSectionState();
}

class _AroundYouSectionState extends ConsumerState<AroundYouSection> {
  AroundFilter _filter = AroundFilter.all;
  double _radiusKm = 15;
  static const _radii = [5.0, 10.0, 15.0, 25.0, 50.0];
  static const _distance = Distance();
  static const _maxCards = 10;

  double _kmTo(ExploreLocation p) =>
      _distance(widget.current!, LatLng(p.latitude, p.longitude)) / 1000;

  @override
  Widget build(BuildContext context) {
    final title = widget.selectedCityName == null
        ? 'Around you'
        : 'Around ${widget.selectedCityName}';

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (widget.current != null)
            PopupMenuButton<double>(
              tooltip: 'How far',
              initialValue: _radiusKm,
              onSelected: (r) => setState(() => _radiusKm = r),
              itemBuilder: (_) => [
                for (final r in _radii)
                  PopupMenuItem(
                    value: r,
                    child: Text('Within ${r.round()} km'),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Within ${_radiusKm.round()} km',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (!widget.hasLocation && widget.selectedCityName == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 10), _locationOff()],
      );
    }

    if (widget.loading || widget.current == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, _row(loading: true)],
      );
    }

    final inReach = [
      for (final p in widget.places)
        if (_kmTo(p) <= _radiusKm) p,
    ];
    // Chips only for kinds there are places of (plus "All").
    final filters = [
      for (final f in AroundFilter.values)
        if (f == AroundFilter.all ||
            f == _filter ||
            inReach.any((p) => f.matches(p.category)))
          f,
    ];
    final shown = inReach
        .where((p) => _filter.matches(p.category))
        .take(_maxCards)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = filters[i];
              final selected = f == _filter;
              return ChoiceChip(
                avatar: Icon(
                  f.icon,
                  size: 16,
                  color: selected ? AppTheme.forest : AppTheme.inkMuted,
                ),
                label: Text(f.label),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f),
                selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppTheme.forest : AppTheme.ink,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if (shown.isEmpty) _empty(inReach.isEmpty) else _row(places: shown),
      ],
    );
  }

  Widget _row({List<ExploreLocation> places = const [], bool loading = false}) {
    final hours = places.isEmpty
        ? const <String, String>{}
        : ref
                  .watch(
                    dayOpeningHoursProvider(
                      encodeHoursQueries([
                        for (final p in places)
                          (
                            key: p.id,
                            placeId: p.id,
                            name: p.name,
                            lat: p.latitude,
                            lng: p.longitude,
                          ),
                      ]),
                    ),
                  )
                  .value ??
              const <String, String>{};

    return SizedBox(
      height: 182, // Taller than the cards so their shadows aren't clipped.
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        clipBehavior: Clip.none,
        itemCount: loading ? 3 : places.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (loading) return const PlaceCardSkeleton();
          if (i == places.length) return const _SeeAllCard();
          final p = places[i];
          return HomePlaceCard(
            place: p,
            distanceKm: _kmTo(p),
            hours: OpeningHours.parse(hours[p.id]),
          );
        },
      ),
    );
  }

  Widget _empty(bool nothingInReach) {
    final String message;
    if (widget.fetchFailed && widget.places.isEmpty) {
      message = "Couldn't look up places near you. Check your internet connection and try again.";
    } else if (nothingInReach) {
      message = 'No places within ${_radiusKm.round()} km yet.';
    } else {
      message =
          'No ${_filter.label.toLowerCase()} within ${_radiusKm.round()} km.';
    }
    final canWiden = _radiusKm < _radii.last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: EmptyStateCard(
        icon: Icons.radar_rounded,
        title: 'Nothing here yet',
        message: message,
        actionLabel: canWiden && widget.places.isNotEmpty
            ? 'Look within ${_radii.last.round()} km'
            : 'Find places nearby',
        onAction: canWiden && widget.places.isNotEmpty
            ? () => setState(() => _radiusKm = _radii.last)
            : widget.onFindNearby,
      ),
    );
  }

  Widget _locationOff() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.amber.withValues(alpha: 0.18),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppTheme.amberText,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Location is off',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Turn on location, or pick any Indian city to see places there.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkMuted,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: const Text('Turn on'),
                        onPressed: widget.onTurnOnLocation,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.location_city_rounded, size: 16),
                        label: const Text('Pick a city'),
                        onPressed: () => showCityPickerModal(context, ref),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
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
    );
  }
}

/// A place card for Home: its photo (its own, else from Wikimedia), kind,
/// XP, distance and whether it's open right now. Undiscovered mystery
/// places keep their secret.
class HomePlaceCard extends ConsumerWidget {
  const HomePlaceCard({
    super.key,
    required this.place,
    required this.distanceKm,
    this.hours,
  });

  final ExploreLocation place;
  final double distanceKm;
  final OpeningHours? hours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visited =
        ref.watch(visitedPlaceIdsProvider).value ?? const <String>{};
    final hidden = place.isMystery && !visited.contains(place.id);

    String? imageUrl;
    if (!hidden) {
      final own = place.imageUrl;
      imageUrl = own != null && own.isNotEmpty
          ? own
          : ref
                .watch(placePhotosProvider(place.photosKey))
                .value
                ?.firstOrNull
                ?.thumbUrl;
    }
    final openNow = hidden ? null : hours?.isOpenAt(DateTime.now());
    final km = distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0);

    return PlaceCard(
      title: hidden ? 'Mystery Place' : place.name,
      // Open/closed leads the one-line subtitle: as an extra label it could
      // wrap and push the title out of the card.
      subtitle: hidden
          ? 'Mystery · +${place.xpReward} XP'
          : [
              if (openNow == true) 'Open now',
              if (openNow == false) 'Closed now',
              place.category.shortLabel,
              '+${place.xpReward} XP',
            ].join(' · '),
      subtitleIcon: hidden
          ? Icons.help_outline_rounded
          : switch (openNow) {
              true => Icons.schedule_rounded,
              false => Icons.do_not_disturb_on_outlined,
              null => Icons.bolt_rounded,
            },
      gradient: hidden
          ? const [Color(0xFF8E2DE2), Color(0xFF4A00E0)]
          : place.category.gradient,
      imageUrl: imageUrl,
      onTap: () =>
          showPlaceSheet(context, place: place, distanceKm: distanceKm),
      pills: [_DarkPill('$km km'), if (hidden) const _DarkPill('???')],
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      MetaPill(label: label, background: Colors.black.withValues(alpha: 0.30));
}

/// The row's last card: everything else is on the map.
class _SeeAllCard extends StatelessWidget {
  const _SeeAllCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: SoftCard(
        onTap: () => context.go('/map'),
        padding: const EdgeInsets.all(12),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: AppTheme.primary, size: 30),
            SizedBox(height: 8),
            Text(
              'See all on the map',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
