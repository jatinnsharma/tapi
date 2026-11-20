import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_components.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../explore/presentation/widgets/city_picker_modal.dart';
import '../locations/data/place_photos_service.dart';
import '../locations/domain/location.dart';
import '../locations/presentation/place_sheet.dart';
import '../locations/presentation/place_style.dart';
import '../planner/data/opening_hours_service.dart';
import '../planner/domain/opening_hours.dart';
import '../preferences/application/preferences_service.dart';
import '../preferences/domain/preference_mapping.dart';
import '../tracking/data/adventure_repository.dart';
import '../weather/application/weather_service.dart';
import '../weather/presentation/weather_advisory_banner.dart';

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
    this.updating = false,
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

  /// Still looking for new places online: an empty list isn't final yet.
  final bool updating;
  final VoidCallback onFindNearby;
  final VoidCallback onTurnOnLocation;
  final String? selectedCityName;

  @override
  ConsumerState<AroundYouSection> createState() => _AroundYouSectionState();
}

class _AroundYouSectionState extends ConsumerState<AroundYouSection> {
  AroundFilter _filter = AroundFilter.all;

  /// The user chose to see places the weather advisory hides.
  bool _showAllWeather = false;
  double _radiusKm = 15;

  /// The user picked a distance here; preferences no longer change it.
  bool _radiusPicked = false;
  static const _radii = [5.0, 10.0, 15.0, 25.0, 50.0];
  static const _distance = Distance();
  static const _maxCards = 10;

  double _kmTo(ExploreLocation p) =>
      _distance(widget.current!, LatLng(p.latitude, p.longitude)) / 1000;

  @override
  Widget build(BuildContext context) {
    // Default distance from how long the user likes to be out.
    if (!_radiusPicked) {
      final prefs = ref.watch(userPreferencesProvider).value;
      final preferred = prefs == null ? null : aroundRadiusKmFor(prefs);
      if (preferred != null && _radii.contains(preferred)) {
        _radiusKm = preferred;
      }
    }
    final title = widget.selectedCityName == null
        ? 'Around you'
        : 'Around ${widget.selectedCityName}';

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          if (widget.current != null)
            PopupMenuButton<double>(
              tooltip: 'How far',
              initialValue: _radiusKm,
              onSelected: (r) => setState(() {
                _radiusKm = r;
                _radiusPicked = true;
              }),
              itemBuilder: (_) => [
                for (final r in _radii)
                  PopupMenuItem(
                    value: r,
                    child: Text('Within ${r.round()} km'),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Within ${_radiusKm.round()} km',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (!widget.hasLocation && widget.selectedCityName == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 10),
          _locationOff(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AppButton.tertiary(
              label: 'Pick a city instead',
              icon: Icons.location_city_rounded,
              onPressed: () => showCityPickerModal(context, ref),
            ),
          ),
        ],
      );
    }

    if (widget.loading || widget.current == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, _row(loading: true)],
      );
    }

    final advisory = ref
        .watch(
          weatherAdvisoryProvider(
            weatherKey(widget.current!.latitude, widget.current!.longitude),
          ),
        )
        .value;
    final nearby = [
      for (final p in widget.places)
        if (_kmTo(p) <= _radiusKm) p,
    ];
    // Bad weather leaves out places it makes unsafe, unless asked not to.
    final filterWeather = advisory != null && !_showAllWeather;
    final inReach = filterWeather
        ? nearby.where((p) => advisory.suits(p.category)).toList()
        : nearby;
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
        if (advisory != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: WeatherAdvisoryBanner(
              advisory: advisory,
              hiddenCount: nearby.length - inReach.length,
              showingAll: _showAllWeather,
              onToggle: () =>
                  setState(() => _showAllWeather = !_showAllWeather),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          // Grows with the text size so large text isn't cut off.
          height: MediaQuery.textScalerOf(context).scale(40).clamp(48, 72),
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
                labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? AppTheme.forest : AppTheme.ink,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if (shown.isNotEmpty)
          _row(places: shown)
        else if (widget.updating)
          // Still looking: not "nothing here" yet.
          _row(loading: true)
        else
          _empty(inReach.isEmpty),
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
      message =
          "Couldn't look up places near you. Check your internet connection "
          'and try again.';
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
            ? () => setState(() {
                _radiusKm = _radii.last;
                _radiusPicked = true; // your choice, not the preference's
              })
            : widget.onFindNearby,
      ),
    );
  }

  Widget _locationOff() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: StatusBanner(
        kind: StatusKind.warning,
        title: 'Location is off',
        message:
            'Turn on location, or pick any Indian city to see places there.',
        actionLabel: 'Turn on',
        onAction: widget.onTurnOnLocation,
        // The second choice sits under the banner.
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
    final hidden = place.isHiddenMystery(visited);

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
      title: place.nameFor(visited),
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
      pills: [_DarkPill('$km km')],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, color: AppTheme.primary, size: 30),
            const SizedBox(height: 8),
            Text(
              'See all on the map',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}
