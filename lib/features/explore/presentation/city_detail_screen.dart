import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/media_shell.dart'
    show mediaOnColor, mediaOnColorMuted, mediaScrim, mediaScrimClear;
import '../../../core/theme/components.dart';
import '../../locations/data/location_repository.dart';
import '../../locations/data/nearby_places_service.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/place_sheet.dart';
import '../../locations/presentation/place_style.dart';
import '../../food/presentation/signature_dishes_section.dart';
import '../../map/map_focus.dart';
import '../../offline/presentation/offline_pack_card.dart';
import '../../tours/presentation/city_tours_section.dart';
import '../../weather/application/weather_service.dart';
import '../../weather/presentation/weather_advisory_banner.dart';
import '../data/city_repository.dart';
import '../domain/city.dart';
import '../../planner/domain/safety_tips.dart';

class CityDetailScreen extends ConsumerStatefulWidget {
  const CityDetailScreen({super.key, required this.cityId});

  final String cityId;

  @override
  ConsumerState<CityDetailScreen> createState() => _CityDetailScreenState();
}

class _CityDetailScreenState extends ConsumerState<CityDetailScreen> {
  LocationCategory? _selectedCategory;

  /// The user chose to see places the weather advisory hides.
  bool _showAllWeather = false;

  /// Reading the city itself (a moment, from the phone).
  bool _isLoading = true;

  /// Still looking for new places online. The page is already showing the
  /// city and whatever places are saved.
  bool _updating = false;

  /// The online lookup failed (offline): saved places are all there is.
  bool _fetchFailed = false;

  /// Why the city couldn't be shown, with whether trying again can help.
  ({String message, bool canRetry})? _error;
  City? _city;
  List<ExploreLocation> _cityPlaces = [];

  @override
  void initState() {
    super.initState();
    _loadCity();
  }

  /// Shows the city and its saved places straight away, then looks for new
  /// places online and adds them when that finishes.
  Future<void> _loadCity({bool force = false}) async {
    setState(() {
      _isLoading = _city == null;
      _error = null;
    });
    try {
      final city =
          _city ??
          await ref.read(cityRepositoryProvider).getCityById(widget.cityId);
      if (!mounted) return;
      if (city == null) {
        setState(() {
          _isLoading = false;
          _error = (
            message: 'We couldn\'t find that city. It may have been removed.',
            canRetry: false,
          );
        });
        return;
      }
      setState(() {
        _city = city;
        _isLoading = false;
        _updating = true;
        _fetchFailed = false;
      });
      await _filterPlaces(); // saved places first

      var failed = false;
      try {
        await ref
            .read(nearbyPlacesServiceProvider)
            .ensureFresh(city.location, force: force);
      } catch (_) {
        failed = true; // fall back to what's saved
      }
      await _filterPlaces();
      if (mounted) {
        setState(() {
          _updating = false;
          _fetchFailed = failed;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _updating = false;
        if (_city == null) {
          _error = (
            message: 'Couldn\'t open this city. Please try again.',
            canRetry: true,
          );
        }
      });
    }
  }

  /// Saved places within 35 km of the city centre, nearest first.
  Future<void> _filterPlaces() async {
    final city = _city;
    if (city == null) return;
    final all = await ref.read(locationRepositoryProvider).getAll();
    const distance = Distance();
    double fromCentre(ExploreLocation p) =>
        distance(city.location, LatLng(p.latitude, p.longitude));
    final nearby = all.where((p) => fromCentre(p) / 1000 <= 35.0).toList()
      ..sort((a, b) => fromCentre(a).compareTo(fromCentre(b)));
    if (!mounted) return;
    setState(() => _cityPlaces = nearby);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _city == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final error = _error;
    if (error != null || _city == null) {
      return Scaffold(
        appBar: AppBar(),
        body: GateCard(
          icon: Icons.location_city_outlined,
          title: error?.canRetry == true
              ? 'Couldn\'t open this city'
              : 'City not found',
          message: error?.message ?? 'We couldn\'t find that city.',
          actionLabel: error?.canRetry == true
              ? 'Try again'
              : 'Back to Explore',
          onAction: error?.canRetry == true
              ? _loadCity
              : () => context.canPop() ? context.pop() : context.go('/explore'),
        ),
      );
    }

    final city = _city!;
    // The city's own weather, not the user's: they may be far away.
    final advisory = ref
        .watch(
          weatherAdvisoryProvider(weatherKey(city.latitude, city.longitude)),
        )
        .value;
    final ofCategory = _selectedCategory == null
        ? _cityPlaces
        : _cityPlaces.where((p) => p.category == _selectedCategory).toList();
    final filtered = advisory == null || _showAllWeather
        ? ofCategory
        : ofCategory.where((p) => advisory.suits(p.category)).toList();

    return Scaffold(
      body: RefreshIndicator(
        // Pull down to look for places again.
        onRefresh: () => _loadCity(force: true),
        edgeOffset: 80,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              leading: _OverPhotoButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/explore'),
              ),
              actions: [
                _OverPhotoButton(
                  icon: Icons.map_outlined,
                  tooltip: 'Explore on Map',
                  onPressed: () {
                    ref
                        .read(mapFocusProvider.notifier)
                        .focus(MapFocus(LatLng(city.latitude, city.longitude)));
                    context.go('/map');
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  city.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: mediaOnColor,
                    shadows: const [Shadow(color: mediaScrim, blurRadius: 6)],
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      city.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppTheme.sage,
                        child: const Center(
                          child: Icon(
                            Icons.location_city,
                            size: 48,
                            color: mediaOnColorMuted,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [mediaScrimClear, mediaScrim],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wraps on small phones with large text.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MetaPill.onLight(label: city.state),
                        MetaPill.onLight(
                          label: prettyCityCategory(city.category),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      city.blurb,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 18),
                    // Plan a Trip Button (Task 9)
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            icon: Icons.auto_awesome,
                            label: 'Plan a trip to ${city.name}',
                            onPressed: () {
                              // The planner gets the city from the link.
                              context.push(
                                Uri(
                                  path: '/trip-planner',
                                  queryParameters: {
                                    'destination': city.name,
                                    'cityId': city.id,
                                  },
                                ).toString(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.shield_outlined),
                          tooltip: 'Safety & local etiquette',
                          onPressed: () => showSafetyTipsModal(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SignatureDishesSection(
                      cityId: city.id,
                      cityName: city.name,
                    ),
                    CityToursSection(cityId: city.id),
                    OfflinePackCard(
                      cityId: city.id,
                      cityName: city.name,
                      center: LatLng(city.latitude, city.longitude),
                    ),
                    Semantics(
                      header: true,
                      child: Text(
                        'Places to explore (${filtered.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryChips(),
                    if (advisory != null) ...[
                      const SizedBox(height: 12),
                      WeatherAdvisoryBanner(
                        advisory: advisory,
                        hiddenCount: ofCategory.length - filtered.length,
                        showingAll: _showAllWeather,
                        onToggle: () =>
                            setState(() => _showAllWeather = !_showAllWeather),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (filtered.isEmpty && _updating)
              // Still looking: not "nothing here" yet.
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: _emptyState(
                    nothingSaved: _cityPlaces.isEmpty,
                    hiddenByWeather:
                        advisory != null &&
                        !_showAllWeather &&
                        ofCategory.isNotEmpty,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final place = filtered[index];
                    return _buildPlaceCard(place);
                  }, childCount: filtered.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final categories = [
      null,
      LocationCategory.heritage,
      LocationCategory.nature,
      LocationCategory.viewpoint,
      LocationCategory.lake,
      LocationCategory.hiddenGem,
      LocationCategory.photography,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          final label = cat == null ? 'All places' : cat.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedCategory = isSelected ? null : cat);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlaceCard(ExploreLocation place) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        onTap: () => showPlaceSheet(context, place: place),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: place.imageUrl != null && place.imageUrl!.isNotEmpty
                    ? Image.network(
                        place.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _gradientPlaceholder(place),
                      )
                    : _gradientPlaceholder(place),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.of(context).textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MetaPill.onLight(label: place.category.shortLabel),
                      Tag(
                        '+${place.xpReward} XP',
                        icon: Icons.bolt_rounded,
                        tone: TagTone.reward,
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

  Widget _emptyState({
    required bool nothingSaved,
    required bool hiddenByWeather,
  }) {
    final String message;
    String? actionLabel;
    VoidCallback? onAction;
    if (hiddenByWeather) {
      message = 'The weather hides these places. Show all to see them.';
      actionLabel = 'Show all';
      onAction = () => setState(() => _showAllWeather = true);
    } else if (nothingSaved) {
      message = _fetchFailed
          ? 'Couldn\'t look up places here. Check your connection and try '
                'again.'
          : 'No places found around ${_city!.name} yet.';
      actionLabel = 'Try again';
      onAction = () => _loadCity(force: true);
    } else {
      message =
          'No ${_selectedCategory?.label.toLowerCase() ?? ''} places '
          'here yet. Try another kind.';
      actionLabel = 'Show all places';
      onAction = () => setState(() => _selectedCategory = null);
    }
    return Column(
      children: [
        Icon(
          Icons.explore_off_outlined,
          size: 48,
          color: AppColors.of(context).textSecondary,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.of(context).textSecondary),
        ),
        const SizedBox(height: 8),
        AppButton.secondary(label: actionLabel, onPressed: onAction),
      ],
    );
  }

  Widget _gradientPlaceholder(ExploreLocation place) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: place.category.gradient,
        ),
      ),
      child: Center(
        child: Text(
          place.category.shortLabel,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
        ),
      ),
    );
  }
}

/// "hill_station" -> "Hill station", for the city's kind.
String prettyCityCategory(String raw) {
  final words = raw.replaceAll('_', ' ').trim().toLowerCase();
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}

/// A round button over the city photo: a dark disc so the icon reads on any
/// picture, a 48 px target and a label for screen readers.
class _OverPhotoButton extends StatelessWidget {
  const _OverPhotoButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: mediaScrim,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: mediaOnColor, size: 20),
      ),
    );
  }
}
