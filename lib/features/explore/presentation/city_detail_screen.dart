import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../locations/data/location_repository.dart';
import '../../locations/data/nearby_places_service.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/place_sheet.dart';
import '../../locations/presentation/place_style.dart';
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
  bool _isLoading = true;
  String? _error;
  City? _city;
  List<ExploreLocation> _cityPlaces = [];

  @override
  void initState() {
    super.initState();
    _loadCity();
  }

  Future<void> _loadCity() async {
    setState(() => _isLoading = true);
    final repo = ref.read(cityRepositoryProvider);
    final city = await repo.getCityById(widget.cityId);
    if (!mounted) return;

    if (city == null) {
      setState(() {
        _isLoading = false;
        _error = 'City not found';
      });
      return;
    }

    _city = city;

    try {
      final placesService = ref.read(nearbyPlacesServiceProvider);
      await placesService.ensureFresh(city.location);
    } catch (_) {
      // Best effort; fall back to cached / stored places
    }

    await _filterPlaces();
  }

  Future<void> _filterPlaces() async {
    if (_city == null) return;
    final locationRepo = ref.read(locationRepositoryProvider);
    final all = await locationRepo.getAll();
    const distance = Distance();

    // Places within 35 km of city center
    final nearby = all.where((p) {
      final d =
          distance(_city!.location, LatLng(p.latitude, p.longitude)) / 1000;
      return d <= 35.0;
    }).toList();

    nearby.sort((a, b) {
      final da = distance(_city!.location, LatLng(a.latitude, a.longitude));
      final db = distance(_city!.location, LatLng(b.latitude, b.longitude));
      return da.compareTo(db);
    });

    if (!mounted) return;
    setState(() {
      _cityPlaces = nearby;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _city == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null || _city == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'City not found'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    final city = _city!;
    final filtered = _selectedCategory == null
        ? _cityPlaces
        : _cityPlaces.where((p) => p.category == _selectedCategory).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                tooltip: 'Explore on Map',
                onPressed: () {
                  ref.read(selectedCityProvider.notifier).select(city);
                  context.go('/map');
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                city.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
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
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
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
                  Row(
                    children: [
                      MetaPill(label: city.state),
                      const SizedBox(width: 8),
                      MetaPill(label: city.category.toUpperCase()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    city.blurb,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Plan a Trip Button (Task 9)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 20),
                          label: Text('Plan a Trip to ${city.name}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            ref
                                .read(selectedCityProvider.notifier)
                                .select(city);
                            // Open AI Trip planner with destination prefilled
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
                        icon: const Icon(Icons.shield_outlined),
                        tooltip: 'Safety & Local Etiquette',
                        onPressed: () => showSafetyTipsModal(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Places to Explore (${filtered.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCategoryChips(),
                ],
              ),
            ),
          ),
          if (_isLoading)
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 32,
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.explore_off_outlined,
                        size: 48,
                        color: AppTheme.inkMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No places found for this category yet.',
                        style: TextStyle(color: AppTheme.inkMuted),
                      ),
                    ],
                  ),
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
          final label = cat == null ? 'All Places' : cat.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedCategory = isSelected ? null : cat);
              },
              selectedColor: AppTheme.primary.withValues(alpha: 0.15),
              checkmarkColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkMuted,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      MetaPill(label: place.category.shortLabel),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 16,
                            color: AppTheme.amberText,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '+${place.xpReward} XP',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.amberText,
                            ),
                          ),
                        ],
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
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
