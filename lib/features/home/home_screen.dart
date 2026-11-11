import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/feature_flags.dart';
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
import '../tracking/application/tracking_service.dart';
import '../tracking/domain/adventure_session.dart';
import '../weather/application/weather_service.dart';
import '../weather/domain/weather_model.dart';
import '../challenges/presentation/daily_challenge_card.dart';
import '../challenges/presentation/streak_flame_badge.dart';
import '../planner/presentation/trip_home_card.dart';
import 'ai_recommendation_card.dart';
import 'around_you_section.dart';

const _pagePadding = EdgeInsets.symmetric(horizontal: 20);

/// Set by the "Find places nearby" button so the next load re-fetches from
/// OpenStreetMap even if the cached fetch is still fresh.
bool _forceNextFetch = false;

final _nearbyLocationsProvider = FutureProvider.autoDispose<_NearbyLocations>((
  ref,
) async {
  final repository = ref.watch(locationRepositoryProvider);
  final locationService = ref.watch(locationServiceProvider);
  final placesService = ref.watch(nearbyPlacesServiceProvider);
  final selectedCity = ref.watch(selectedCityProvider);

  final located = await locationService.getCurrentLocation();
  final current =
      selectedCity?.location ?? located ?? ServiceArea.defaultCenter;

  String? fetchError;
  final force = _forceNextFetch;
  _forceNextFetch = false;
  try {
    await placesService.ensureFresh(current, force: force);
  } catch (e) {
    fetchError = '$e';
  }

  final all = await repository.getAll();

  return _NearbyLocations(
    current: current,
    hasLocation: located != null || selectedCity != null,
    sorted: repository.sortedByDistance(all, current),
    fetchFailed: fetchError != null,
  );
});

class _NearbyLocations {
  const _NearbyLocations({
    required this.current,
    required this.hasLocation,
    required this.sorted,
    required this.fetchFailed,
  });

  final LatLng current;

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

    // The adventure in progress, if any: Home is the way back to it.
    final session = ref.watch(trackingServiceProvider).session;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.forest,
          onRefresh: () async {
            ref.invalidate(_nearbyLocationsProvider);
            ref.invalidate(currentWeatherProvider);
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
                    name: name,
                    weather: weather,
                    locating: nearbyAsync.isLoading,
                    hasLocation: nearbyAsync.value?.hasLocation ?? true,
                    selectedCityName: selectedCity?.name,
                  ),
                ),
              ),
              if (session != null) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: _pagePadding,
                  child: _ContinueAdventureCard(
                    title: session.title,
                    paused: session.status == AdventureStatus.paused,
                    onTap: () => context.push('/tracking'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: Padding(
                  padding: _pagePadding,
                  child: Text(
                    'Where to next?',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: 38, letterSpacing: -1),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const FadeSlideIn(
                delay: Duration(milliseconds: 80),
                child: Padding(
                  padding: _pagePadding,
                  child: ExploreSearchBar(),
                ),
              ),
              const SizedBox(height: 18),
              const FadeSlideIn(
                delay: Duration(milliseconds: 100),
                child: Padding(padding: _pagePadding, child: TripHomeCard()),
              ),
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: NearbyCitiesSection(
                  userLocation: nearbyAsync.value?.hasLocation == true
                      ? nearbyAsync.value?.current
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: nearbyAsync.hasError && !nearbyAsync.hasValue
                    ? Padding(
                        padding: _pagePadding,
                        child: EmptyStateCard(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load nearby places',
                          message: '${nearbyAsync.error}',
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
                        onFindNearby: _findPlacesNearby,
                        onTurnOnLocation: _turnOnLocation,
                        selectedCityName: selectedCity?.name,
                      ),
              ),
              const SizedBox(height: 10),
              const FadeSlideIn(
                delay: Duration(milliseconds: 160),
                child: Padding(
                  padding: _pagePadding,
                  child: DailyChallengeCard(),
                ),
              ),
              const SizedBox(height: 16),
              const FadeSlideIn(
                delay: Duration(milliseconds: 180),
                child: Padding(padding: _pagePadding, child: _QuickActions()),
              ),
              const SizedBox(height: 16),
              // Free exploration, without a set destination.
              FadeSlideIn(
                delay: const Duration(milliseconds: 200),
                child: Padding(
                  padding: _pagePadding,
                  child: _HeroSection(
                    weather: weather,
                    adventureInProgress: session != null,
                    onStart: () => context.push('/tracking'),
                  ),
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
    required this.name,
    required this.weather,
    required this.locating,
    required this.hasLocation,
    this.selectedCityName,
  });

  final String? selectedCityName;

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
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppTheme.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const StreakFlameBadge(),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Exploration Preferences',
          onPressed: () => context.push('/preferences'),
        ),
        const SizedBox(width: 10),
        RoundIconButton(
          icon: Icons.bookmark_outline_rounded,
          tooltip: 'Wishlist',
          onPressed: () => context.push('/wishlist'),
        ),
      ],
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.weather,
    required this.adventureInProgress,
    required this.onStart,
  });

  final WeatherData? weather;
  final bool adventureInProgress;
  final VoidCallback onStart;

  IconData get _weatherIcon {
    final code = weather?.weatherCode ?? 0;
    if (code == 0) {
      return weather?.isDay == false
          ? Icons.nightlight_outlined
          : Icons.wb_sunny_outlined;
    }
    if (code <= 3) return Icons.wb_cloudy_outlined;
    if (code <= 48) return Icons.foggy;
    if (code >= 95) return Icons.thunderstorm_outlined;
    if (code >= 71 && code <= 75) return Icons.ac_unit;
    return Icons.grain;
  }

  @override
  Widget build(BuildContext context) {
    final current = weather;
    return HeroCard(
      minHeight: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (current != null)
                MetaPill(
                  icon: _weatherIcon,
                  label:
                      '${current.conditionDescription} · ${current.temperature.round()}°',
                ),
              if (adventureInProgress)
                const MetaPill(
                  icon: Icons.hiking_rounded,
                  label: 'Adventure in progress',
                ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Ready for your next adventure?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AmberPillButton(
                label: adventureInProgress ? 'Resume' : 'Start',
                onPressed: onStart,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown on Home while an adventure is running (or paused), so there's
/// always a one-tap way back to it.
class _ContinueAdventureCard extends StatelessWidget {
  const _ContinueAdventureCard({
    required this.title,
    required this.paused,
    required this.onTap,
  });

  final String title;
  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.emerald, AppTheme.forest],
              ),
            ),
            child: const Icon(Icons.hiking_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paused ? 'Adventure paused' : 'Adventure in progress',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.amberText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            child: Text(paused ? 'Resume' : 'Continue'),
          ),
        ],
      ),
    );
  }
}

/// Shortcuts to features that used to live in the app bar.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.auto_awesome, 'Trip Planner', '/trip-planner'),
      (Icons.photo_library_outlined, 'Memories', '/memories'),
      if (FeatureFlags.ecosystem)
        (Icons.storefront_outlined, 'Ecosystem', '/ecosystem'),
      (Icons.menu_book_outlined, 'Journal', '/journal'),
      (Icons.calendar_month_rounded, 'Calendar', '/calendar'),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: PressableScale(
              child: SoftCard(
                radius: 20,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onTap: () => context.push(actions[i].$3),
                child: Column(
                  children: [
                    Icon(actions[i].$1, color: AppTheme.primaryGreen, size: 24),
                    const SizedBox(height: 6),
                    Text(
                      actions[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
