import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/service_area.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../../core/theme/glass.dart';
import '../auth/application/display_name_provider.dart';
import '../explore/data/city_repository.dart';
import '../explore/presentation/widgets/explore_search_bar.dart';
import '../explore/presentation/widgets/nearby_cities_section.dart';
import '../locations/data/location_repository.dart';
import '../locations/data/nearby_places_service.dart';
import '../locations/domain/location.dart';
import '../weather/application/weather_service.dart';
import '../weather/domain/weather_model.dart';
import '../challenges/presentation/daily_challenge_card.dart';
import '../challenges/presentation/streak_flame_badge.dart';
import '../planner/presentation/trip_home_card.dart';
import 'ai_recommendation_card.dart';
import 'around_you_section.dart';
import '../../core/ui/friendly_error.dart';
import '../planner/data/saved_trips_repository.dart';
import '../explore/presentation/widgets/city_picker_modal.dart';

const _pagePadding = EdgeInsets.symmetric(horizontal: 20);

/// Set by the "Find places nearby" button so the next load re-fetches from
/// OpenStreetMap even if the cached fetch is still fresh.
bool _forceNextFetch = false;

/// Places around you. Shows what's already saved on the phone straight
/// away, then looks for new ones online and updates the list when that
/// finishes (so a slow or offline connection never keeps the screen empty).
final _nearbyLocationsProvider = StreamProvider.autoDispose<_NearbyLocations>((
  ref,
) async* {
  final repository = ref.watch(locationRepositoryProvider);
  final locationService = ref.watch(locationServiceProvider);
  final placesService = ref.watch(nearbyPlacesServiceProvider);
  final selectedCity = ref.watch(selectedCityProvider);

  // A position from the last few minutes is plenty for "near me", and
  // instant; waiting for a fresh fix could take 10 seconds.
  final located = await locationService.getCurrentLocation(acceptRecent: true);
  final current =
      selectedCity?.location ?? located ?? ServiceArea.defaultCenter;
  final hasLocation = located != null || selectedCity != null;

  _NearbyLocations result(
    List<ExploreLocation> all, {
    bool failed = false,
    bool updating = false,
  }) => _NearbyLocations(
    current: current,
    hasLocation: hasLocation,
    sorted: repository.sortedByDistance(all, current),
    fetchFailed: failed,
    updating: updating,
  );

  final force = _forceNextFetch;
  _forceNextFetch = false;

  // Saved places first (skipped when there are none, so a new user sees the
  // loading state, not a flash of "no places").
  final saved = await repository.getAll();
  if (saved.isNotEmpty) yield result(saved, updating: true);

  var failed = false;
  try {
    await placesService.ensureFresh(current, force: force);
  } catch (_) {
    failed = true;
  }
  yield result(await repository.getAll(), failed: failed);
});

class _NearbyLocations {
  const _NearbyLocations({
    required this.current,
    required this.hasLocation,
    required this.sorted,
    required this.fetchFailed,
    this.updating = false,
  });

  final LatLng current;

  /// Still looking for new places online (the list is what's saved so far).
  final bool updating;

  /// True when looking up nearby places online failed (e.g. offline).
  final bool fetchFailed;

  /// False when location is off/denied and [current] is only a fallback.
  final bool hasLocation;

  /// Every place, nearest first.
  final List<ExploreLocation> sorted;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _turnOnLocation() async {
    await ref.read(locationServiceProvider).requestPermission();
    ref.invalidate(_nearbyLocationsProvider);
    ref.invalidate(currentWeatherProvider);
  }

  /// Re-runs the nearby search against OpenStreetMap right now.
  void _findPlacesNearby() {
    _forceNextFetch = true;
    ref.invalidate(_nearbyLocationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final nearbyAsync = ref.watch(_nearbyLocationsProvider);
    final weather = ref.watch(currentWeatherProvider).value;
    final name = ref.watch(displayNameProvider);
    final selectedCity = ref.watch(selectedCityProvider);

    // A trip today, coming up or being planned takes the "Now" slot.
    final trips = ref.watch(savedTripsListProvider).value ?? const [];
    final hasFeaturedTrip = pickHomeTrip(trips, DateTime.now()) != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.forest,
          // The spinner stays until the new places have arrived.
          onRefresh: () async {
            ref.invalidate(currentWeatherProvider);
            ref.invalidate(_nearbyLocationsProvider);
            try {
              await ref.read(_nearbyLocationsProvider.future);
            } catch (_) {
              // The error card below says what went wrong.
            }
          },
          // Ordered by "what am I doing now?": the trip in progress, your
          // trip, search, then browsing.
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              FadeSlideIn(
                child: Padding(
                  padding: _pagePadding,
                  child: _Header(
                    onPickCity: () => showCityPickerModal(context, ref),
                    name: name,
                    weather: weather,
                    locating: nearbyAsync.isLoading,
                    hasLocation: nearbyAsync.value?.hasLocation ?? true,
                    selectedCityName: selectedCity?.name,
                  ),
                ),
              ),
              // A running trip is resumed from the bar above the tabs.
              const SizedBox(height: 16),
              const FadeSlideIn(
                delay: Duration(milliseconds: 60),
                child: Padding(
                  padding: _pagePadding,
                  child: ExploreSearchBar(),
                ),
              ),
              const SizedBox(height: 20),
              // "Now": your trip if there is one, else start exploring.
              FadeSlideIn(
                delay: const Duration(milliseconds: 100),
                child: Padding(
                  padding: _pagePadding,
                  child: hasFeaturedTrip
                      ? const TripHomeCard()
                      : _StartExploringCard(
                          weather: weather,
                          onStart: () => context.push('/tracking'),
                          onPlan: () => context.push('/trip-planner'),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const FadeSlideIn(
                delay: Duration(milliseconds: 120),
                child: Padding(
                  padding: _pagePadding,
                  child: DailyChallengeCard(),
                ),
              ),
              const SizedBox(height: 24),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: nearbyAsync.hasError && !nearbyAsync.hasValue
                    ? Padding(
                        padding: _pagePadding,
                        child: EmptyStateCard(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load nearby places',
                          message: friendlyError(nearbyAsync.error!),
                          actionLabel: 'Try again',
                          onAction: () =>
                              ref.invalidate(_nearbyLocationsProvider),
                        ),
                      )
                    : AroundYouSection(
                        current: nearbyAsync.value?.current,
                        hasLocation: nearbyAsync.value?.hasLocation ?? true,
                        places: nearbyAsync.value?.sorted ?? const [],
                        loading: nearbyAsync.isLoading && !nearbyAsync.hasValue,
                        fetchFailed: nearbyAsync.value?.fetchFailed ?? false,
                        updating:
                            (nearbyAsync.value?.updating ?? false) ||
                            nearbyAsync.isLoading,
                        onFindNearby: _findPlacesNearby,
                        onTurnOnLocation: _turnOnLocation,
                        selectedCityName: selectedCity?.name,
                      ),
              ),
              const SizedBox(height: 8),
              FadeSlideIn(
                delay: const Duration(milliseconds: 160),
                child: NearbyCitiesSection(
                  userLocation: nearbyAsync.value?.hasLocation == true
                      ? nearbyAsync.value?.current
                      : null,
                ),
              ),
              // Hidden unless a Gemini key is set up.
              if (nearbyAsync.value case final nearby?)
                Padding(
                  padding: _pagePadding,
                  child: AiRecommendationCard(
                    nearbyLocations: nearby.sorted.take(12).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onPickCity,
    required this.name,
    required this.weather,
    required this.locating,
    required this.hasLocation,
    this.selectedCityName,
  });

  final String? selectedCityName;

  /// Opens the city picker (the location line is a button).
  final VoidCallback onPickCity;

  final String? name;
  final WeatherData? weather;
  final bool locating;
  final bool hasLocation;

  String get _greeting {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'morning'
        : hour < 17
        ? 'afternoon'
        : 'evening';
    return name == null ? 'Good $part' : 'Good $part, $name';
  }

  String get _locationLine {
    if (locating) return 'Finding your location…';
    if (selectedCityName != null) return 'Exploring $selectedCityName';
    if (!hasLocation) return 'Location off · Exploring India';
    final temp = weather == null ? '' : ' · ${weather!.temperature.round()}°C';
    return 'Near you$temp';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppAvatar(initial: name ?? 'E', size: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.inkMuted),
              ),
              const SizedBox(height: 2),
              // The location is a button: tap to explore another city.
              Semantics(
                button: true,
                label: 'Location: $_locationLine. Change city',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onPickCity,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: AppTheme.forest,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _locationLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: AppTheme.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const StreakFlameBadge(),
        const SizedBox(width: 4),
        // One menu instead of three icons: leaves room for the greeting on
        // narrow phones (it used to get about 27 px at 360 dp).
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.ink),
          onSelected: (route) => context.push(route),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: '/safety',
              child: ListTile(
                leading: Icon(Icons.health_and_safety_outlined),
                title: Text('Safety & SOS'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: '/wishlist',
              child: ListTile(
                leading: Icon(Icons.bookmark_outline_rounded),
                title: Text('Wishlist'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: '/preferences',
              child: ListTile(
                leading: Icon(Icons.tune_rounded),
                title: Text('Preferences'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The "Now" card when there's no trip: one main action (start exploring),
/// with planning a trip as the alternative.
class _StartExploringCard extends StatelessWidget {
  const _StartExploringCard({
    required this.weather,
    required this.onStart,
    required this.onPlan,
  });

  final WeatherData? weather;
  final VoidCallback onStart;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onHero = Theme.of(context).colorScheme.onPrimary;
    final current = weather;
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore around you',
            style: text.headlineSmall?.copyWith(color: onHero),
          ),
          const SizedBox(height: 4),
          Text(
            current == null
                ? 'Walk to places nearby and earn XP for each one you reach.'
                : '${current.conditionDescription}, '
                      '${current.temperature.round()}°. Walk to places nearby '
                      'and earn XP for each one you reach.',
            style: text.bodyMedium?.copyWith(
              color: onHero.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: onHero,
                  foregroundColor: AppTheme.forest,
                ),
                icon: const Icon(Icons.directions_walk_rounded),
                label: const Text('Start exploring'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onPlan,
                style: TextButton.styleFrom(foregroundColor: onHero),
                child: const Text('Plan a trip'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
