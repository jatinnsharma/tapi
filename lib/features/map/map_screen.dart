import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/service_area.dart';
import '../../core/services/firebase_status.dart';
import '../../core/services/ai_status.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../../core/theme/app_components.dart';
import '../ai/application/ai_places_service.dart';
import '../auth/application/auth_service.dart';
import '../social/data/social_repository.dart';
import 'application/fog_service.dart';
import '../locations/data/location_community_repository.dart';
import '../locations/data/location_repository.dart';
import '../locations/domain/location.dart';
import '../locations/presentation/place_sheet.dart';
import '../wishlist/application/wishlist_service.dart';
import '../wishlist/domain/wishlist_entry.dart';
import '../tracking/data/adventure_repository.dart';
import '../tracking/domain/route_point.dart';
import '../social/domain/footprint.dart';
import '../social/domain/friendship.dart';
import 'person_marker.dart';
import 'map_pin.dart';
import '../../core/config/memories_api.dart';
import '../food/data/food_repository.dart';
import '../memories/data/shared_memory_service.dart';
import '../memories/domain/capsule_watch.dart';
import '../memories/domain/shared_memory.dart';
import '../memories/presentation/capsule_sheet.dart';
import '../food/domain/food.dart';
import '../food/presentation/food_spot_sheet.dart';
import 'map_focus.dart';
import 'osm_tiles.dart';
import '../../core/ui/friendly_error.dart';

enum MapMode {
  /// The default "fog of exploration" behavior: only discovered locations
  /// plus a faint preview of undiscovered ones nearby.
  exploring,

  /// The spec's "view full map for planning" escape hatch — every location,
  /// fog ignored.
  fullMap,

  /// The spec's §30 "Personal Exploration Map": only places the user has
  /// actually been, or has saved to their wishlist to go to.
  myPlaces,

  /// Social heatmap showing friends' paths.
  social,
}

extension on MapMode {
  String get label => switch (this) {
    MapMode.exploring => 'Nearby',
    MapMode.fullMap => 'Everything',
    MapMode.myPlaces => 'Mine',
    MapMode.social => 'Friends',
  };

  String get description => switch (this) {
    MapMode.exploring => 'Places appear as you explore. Unknown ones stay hidden until you get close.',
    MapMode.fullMap => 'Every place, for planning a trip anywhere.',
    MapMode.myPlaces => 'Places you\'ve found or saved, and your routes.',
    MapMode.social => 'Routes your friends chose to share.',
  };

  IconData get icon => switch (this) {
    MapMode.exploring => Icons.explore_outlined,
    MapMode.fullMap => Icons.public_rounded,
    MapMode.myPlaces => Icons.bookmark_outline_rounded,
    MapMode.social => Icons.group_outlined,
  };
}

final completedPathsProvider =
    FutureProvider.autoDispose<List<List<RoutePoint>>>((ref) async {
      final repository = ref.watch(adventureRepositoryProvider);
      return repository.getAllCompletedRoutePaths();
    });

final socialPathsProvider = FutureProvider.autoDispose<List<List<LatLng>>>((
  ref,
) async {
  if (!ref.read(firebaseReadyProvider)) return [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];

  final socialRepo = ref.watch(socialRepositoryProvider);
  final friendships = await socialRepo.getFriendshipsFor(user.uid);
  final friendUids = friendships
      .where((f) => f.status == FriendshipStatus.accepted)
      .map((f) => f.uidA == user.uid ? f.uidB : f.uidA)
      .toList();

  // Friends' routes come from their footprints, so only friends who chose
  // to share (Friends or Public) appear; the rest are skipped silently.
  final paths = <List<LatLng>>[];
  for (final friendUid in friendUids) {
    try {
      final footprint = await socialRepo.getFootprint(friendUid);
      if (footprint != null &&
          footprint.visibility != FootprintVisibility.private) {
        paths.addAll(footprint.decodedRoutes);
      }
    } catch (_) {
      // Not shared with us (permission denied): skip.
    }
  }
  return paths;
});

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<LatLng>? _locationSubscription;
  StreamSubscription<void>? _placesSubscription;
  LatLng? _currentLocation;

  /// False while showing the default area because location is off.
  bool _hasFix = false;
  List<ExploreLocation> _locations = [];
  bool _isLoading = true;
  bool _isGenerating = false;

  /// Audio capsules around the user, and which were already announced.
  List<SharedMemory> _capsules = const [];
  final _announcedCapsules = <String>{};
  DateTime? _capsulesFetchedAt;
  LatLng? _capsulesFetchedWhere;
  bool _fetchingCapsules = false;

  /// The Food layer: real places to eat from OpenStreetMap.
  bool _showFood = false;
  bool _loadingFood = false;
  List<FoodSpot> _foodSpots = const [];
  MapMode _mode = MapMode.exploring;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final locationService = ref.read(locationServiceProvider);
    final repository = ref.read(locationRepositoryProvider);

    final allLocations = await repository.getAll();
    final location = await locationService.getCurrentLocation();
    final current = location ?? ServiceArea.center;

    final fogService = ref.read(fogServiceProvider);
    final revealed = await fogService.processPosition(current, allLocations);

    if (!mounted) return;
    setState(() {
      _currentLocation = current;
      _hasFix = location != null;
      _locations = revealed;
      _isLoading = false;
    });
    unawaited(_syncNewlyDiscoveredBestEffort(allLocations, revealed));
    if (location != null) unawaited(_checkCapsules(location));

    _locationSubscription = locationService.getLocationStream().listen(
      _onLocationUpdate,
    );
    // Places fetched elsewhere (a city's page, search, the planner) show up
    // here without leaving the tab.
    _placesSubscription = repository.changes.listen((_) => _reloadPlaces());

    // "Explore on Map" may have been tapped before this tab first opened.
    final pending = ref.read(mapFocusProvider);
    if (pending != null) _applyFocus(pending);
  }

  Future<void> _reloadPlaces() async {
    final current = _currentLocation;
    if (current == null) return;
    final all = await ref.read(locationRepositoryProvider).getAll();
    final revealed = await ref
        .read(fogServiceProvider)
        .processPosition(current, all);
    if (!mounted) return;
    setState(() => _locations = revealed);
  }

  /// Shows [focus] (e.g. a city picked elsewhere): every place, fog off,
  /// since it may be far from the user, and the map moved there.
  void _applyFocus(MapFocus focus) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mapFocusProvider.notifier).clear();
      setState(() => _mode = MapMode.fullMap);
      _mapController.move(focus.center, focus.zoom);
    });
  }

  /// Fetches nearby capsules now and then, and announces one the user
  /// walks up to (a buzz and a "Listen" prompt). Quietly does nothing when
  /// signed out, offline or without a memories server.
  Future<void> _checkCapsules(LatLng here) async {
    if (memoriesApiUrl.isEmpty || !ref.read(firebaseReadyProvider)) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    final now = DateTime.now();
    if (!_fetchingCapsules &&
        shouldFetchCapsules(
          now: now,
          here: here,
          lastAt: _capsulesFetchedAt,
          lastWhere: _capsulesFetchedWhere,
        )) {
      _fetchingCapsules = true;
      try {
        final found = await ref
            .read(sharedMemoryServiceProvider)
            .nearbyCapsules(
              uid: user.uid,
              latitude: here.latitude,
              longitude: here.longitude,
            );
        _capsulesFetchedAt = now;
        _capsulesFetchedWhere = here;
        if (mounted) setState(() => _capsules = found);
      } catch (_) {
        // Try again on a later update.
      } finally {
        _fetchingCapsules = false;
      }
    }
    if (!mounted) return;
    final reached = capsulesToAnnounce(
      _capsules,
      here,
      announced: _announcedCapsules,
    );
    if (reached.isEmpty) return;
    final capsule = reached.first;
    _announcedCapsules.addAll(reached.map((c) => c.id));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          'Voice note here: '
          '"${capsule.caption ?? 'A note'}" by ${capsule.displayName}',
        ),
        action: SnackBarAction(
          label: 'Listen',
          onPressed: () => showCapsuleSheet(context, capsule),
        ),
      ),
    );
  }

  Future<void> _onLocationUpdate(LatLng position) async {
    unawaited(_checkCapsules(position));
    final fogService = ref.read(fogServiceProvider);
    final previous = _locations;
    final revealed = await fogService.processPosition(position, previous);
    if (!mounted) return;
    setState(() {
      _currentLocation = position;
      _hasFix = true;
      _locations = revealed;
    });
    unawaited(_syncNewlyDiscoveredBestEffort(previous, revealed));
  }

  Future<void> _generateNearbyPlaces() async {
    if (_currentLocation == null) return;
    final aiReady = ref.read(aiReadyProvider);
    if (!aiReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("AI suggestions aren't available in this version yet."),
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      // Search around the user's location, otherwise around the center
      final anchor = _currentLocation ?? ServiceArea.center;
      final aiService = ref.read(aiPlacesServiceProvider);
      final newLocations =
          (await aiService.generateNearbyLocations(
                anchor.latitude,
                anchor.longitude,
              ))
              .where(
                (l) => ServiceArea.containsCoordinates(l.latitude, l.longitude),
              )
              .toList();

      final repository = ref.read(locationRepositoryProvider);
      await repository.insertMany(newLocations);

      final allLocations = await repository.getAll();
      final fogService = ref.read(fogServiceProvider);
      final revealed = await fogService.processPosition(
        _currentLocation!,
        allLocations,
      );

      if (!mounted) return;
      setState(() {
        _locations = revealed;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newLocations.isEmpty
                ? 'No new places found near here.'
                : 'Added ${newLocations.length} places nearby. '
                      'Explore to reveal them.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t suggest places. ${friendlyError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// Counts the user as an explorer of each newly-revealed location in the
  /// shared Firestore community layer (spec §44) — purely additive to the
  /// personal fog-of-war mechanic above, which stays entirely local. Never
  /// throws; this is a social nicety, not the discovery mechanic itself.
  Future<void> _syncNewlyDiscoveredBestEffort(
    List<ExploreLocation> before,
    List<ExploreLocation> after,
  ) async {
    try {
      if (!ref.read(firebaseReadyProvider)) return;
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final beforeDiscovered = {for (final l in before) l.id: l.isDiscovered};
      final community = ref.read(locationCommunityRepositoryProvider);
      for (final location in after) {
        if (location.isDiscovered && beforeDiscovered[location.id] != true) {
          await community.recordVisitIfNew(location.id, user.uid);
        }
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Turns the Food layer on (fetching around the map's centre) or off.
  Future<void> _toggleFood() async {
    if (_showFood) {
      setState(() => _showFood = false);
      return;
    }
    setState(() => _showFood = true);
    await _loadFoodHere();
  }

  Future<void> _loadFoodHere() async {
    final center = _mapController.camera.center;
    setState(() => _loadingFood = true);
    try {
      final spots = await ref
          .read(foodRepositoryProvider)
          .spotsNear(center.latitude, center.longitude);
      if (!mounted) return;
      setState(() => _foodSpots = spots);
      if (spots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No places to eat mapped near here.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load places to eat. Check your connection.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingFood = false);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _placesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _centerOnUser() async {
    final locationService = ref.read(locationServiceProvider);
    var location = await locationService.getCurrentLocation();
    if (location == null) {
      await locationService.requestPermission();
      location = await locationService.getCurrentLocation();
    }
    if (!mounted) return;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on location to see where you are.')),
      );
      return;
    }
    final here = location;
    setState(() {
      _currentLocation = here;
      _hasFix = true;
    });
    _mapController.move(here, 15.0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MapFocus?>(mapFocusProvider, (_, next) {
      if (next != null && !_isLoading) _applyFocus(next);
    });
    if (_isLoading) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: AppSpacing.page,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(
                  child: Shimmer(child: SkeletonBox(radius: 32)),
                ),
                const Tag(
                  'Finding your location…',
                  icon: Icons.my_location,
                  tone: TagTone.brand,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final wishlistKeysAsync = ref.watch(wishlistKeysProvider);
    final wishlistedLocationIds = wishlistKeysAsync.maybeWhen(
      data: (keys) => keys
          .where((key) => key.startsWith('${WishlistType.location.name}:'))
          .map((key) => key.split(':').last)
          .toSet(),
      orElse: () => <String>{},
    );

    final visitedIds =
        ref.watch(visitedPlaceIdsProvider).value ?? const <String>{};
    // A place reached on a trip counts as discovered even if the map wasn't
    // open to reveal it at the time.
    final locations = [
      for (final l in _locations)
        visitedIds.contains(l.id) && !l.isDiscovered
            ? l.copyWith(discoveredAt: DateTime.now())
            : l,
    ];

    final fogService = ref.read(fogServiceProvider);
    final visible = switch (_mode) {
      MapMode.exploring => fogService.visibleLocations(
        locations,
        _currentLocation!,
      ),
      MapMode.fullMap => locations,
      MapMode.myPlaces =>
        locations
            .where(
              (l) => l.isDiscovered || wishlistedLocationIds.contains(l.id),
            )
            .toList(),
      MapMode.social => locations.where((l) => l.isDiscovered).toList(),
    };
    final visitedCount = locations
        .where((l) => visitedIds.contains(l.id))
        .length;

    final layersChanged = _mode != MapMode.exploring || _showFood;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          if (_isGenerating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: layersChanged,
              smallSize: 8,
              child: AppButton.tertiary(
                label: 'Layers',
                icon: Icons.layers_outlined,
                onPressed: _showLayers,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? ServiceArea.center,
              initialZoom: _currentLocation != null ? 14.0 : 12.0,
            ),
            children: [
              osmTileLayer(),
              if (_mode == MapMode.myPlaces)
                Consumer(
                  builder: (context, ref, _) {
                    final pathsAsync = ref.watch(completedPathsProvider);
                    return pathsAsync.maybeWhen(
                      data: (paths) => PolylineLayer(
                        polylines: [
                          for (final path in paths)
                            Polyline(
                              points: path
                                  .map((p) => LatLng(p.latitude, p.longitude))
                                  .toList(),
                              color: AppTheme.emerald.withValues(alpha: 0.55),
                              strokeWidth: 4.0,
                            ),
                        ],
                      ),
                      orElse: () => const SizedBox.shrink(),
                    );
                  },
                ),
              if (_mode == MapMode.social)
                Consumer(
                  builder: (context, ref, _) {
                    final socialPathsAsync = ref.watch(socialPathsProvider);
                    return socialPathsAsync.maybeWhen(
                      data: (paths) => PolylineLayer(
                        polylines: [
                          for (final path in paths)
                            Polyline(
                              points: path,
                              color: AppTheme.amber.withValues(alpha: 0.65),
                              strokeWidth: 4.0,
                            ),
                        ],
                      ),
                      orElse: () => const SizedBox.shrink(),
                    );
                  },
                ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null) personMarker(_currentLocation!),
                  for (final location in visible)
                    Marker(
                      point: LatLng(location.latitude, location.longitude),
                      width: MapPin.tapSize,
                      height: MapPin.tapSize,
                      child: _pinFor(
                        location,
                        visitedIds: visitedIds,
                        isWishlisted: wishlistedLocationIds.contains(
                          location.id,
                        ),
                      ),
                    ),
                ],
              ),
              if (_capsules.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final c in _capsules)
                      if (c.latitude != null && c.longitude != null)
                        Marker(
                          point: LatLng(c.latitude!, c.longitude!),
                          width: MapPin.tapSize,
                          height: MapPin.tapSize,
                          child: MapPin.voice(
                            label: c.caption ?? 'A note',
                            onTap: () => showCapsuleSheet(context, c),
                          ),
                        ),
                  ],
                ),
              if (_showFood)
                MarkerLayer(
                  markers: [
                    for (final spot in _foodSpots)
                      Marker(
                        point: LatLng(spot.latitude, spot.longitude),
                        width: MapPin.tapSize,
                        height: MapPin.tapSize,
                        child: MapPin.food(
                          label: spot.name,
                          onTap: () => showFoodSpotSheet(context, spot),
                        ),
                      ),
                  ],
                ),
              const OsmAttribution(),
            ],
          ),
          if (!_hasFix)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: StatusBanner(
                kind: StatusKind.warning,
                title: 'Location is off',
                message:
                    'Showing a default area. Turn on location to explore '
                    'around you.',
                actionLabel: 'Turn on',
                onAction: _centerOnUser,
              ),
            ),
          if (_showFood)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: _loadingFood ? null : _loadFoodHere,
                  icon: _loadingFood
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Search this area'),
                ),
              ),
            )
          else if (visitedCount > 0)
            Positioned(
              bottom: 28,
              left: 16,
              child: IgnorePointer(
                child: Material(
                  color: AppColors.of(context).surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  elevation: 1,
                  child: Tag(
                    '$visitedCount visited',
                    icon: Icons.check_circle_rounded,
                    tone: TagTone.brand,
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 20,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canLeaveVoiceNotes) ...[
                  RoundIconButton(
                    icon: Icons.mic_none_rounded,
                    size: 48,
                    tooltip: 'Leave a voice note here',
                    onPressed: () => leaveAudioCapsule(context, ref),
                  ),
                  const SizedBox(height: 12),
                ],
                RoundIconButton(
                  icon: Icons.my_location,
                  size: 54,
                  tooltip: 'Center on my location',
                  onPressed: _centerOnUser,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Voice notes need sign-in and the memories server; otherwise the
  /// button is hidden rather than failing on tap.
  bool get _canLeaveVoiceNotes =>
      memoriesApiUrl.isNotEmpty &&
      ref.watch(firebaseReadyProvider) &&
      ref.watch(authStateProvider).value != null;

  Widget _pinFor(
    ExploreLocation location, {
    required Set<String> visitedIds,
    required bool isWishlisted,
  }) {
    void open() => _openPlace(location);
    if (visitedIds.contains(location.id)) {
      return MapPin.visited(
        icon: location.category.icon,
        label: location.nameFor(visitedIds),
        onTap: open,
      );
    }
    if (location.isDiscovered) {
      final hidden = location.isHiddenMystery(visitedIds);
      return MapPin(
        icon: hidden ? Icons.help_outline_rounded : location.category.icon,
        color: location.category.color,
        label: location.nameFor(visitedIds),
        onTap: open,
      );
    }
    if (_mode == MapMode.myPlaces && isWishlisted) {
      return MapPin.saved(label: location.name, onTap: open);
    }
    return MapPin.unknown(onTap: open);
  }

  /// Opens the shared place sheet. Places under the fog open as "Unknown
  /// place", with no name, photos or saving.
  void _openPlace(ExploreLocation location) {
    final here = _currentLocation;
    final km = _hasFix && here != null
        ? const Distance().as(
                LengthUnit.Meter,
                here,
                LatLng(location.latitude, location.longitude),
              ) /
              1000
        : null;
    showPlaceSheet(
      context,
      place: location,
      distanceKm: km,
      undiscovered: !location.isDiscovered,
    );
  }

  /// What the map shows, the Food layer, AI suggestions and the legend,
  /// all in one sheet.
  void _showLayers() {
    final aiReady = ref.read(aiReadyProvider);
    showAppSheet<void>(
      context,
      title: 'Map layers',
      body: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final text = Theme.of(sheetContext).textTheme;
          final colors = AppColors.of(sheetContext);
          final brand = Theme.of(sheetContext).colorScheme.primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppListGroup(
                title: 'SHOW',
                children: [
                  for (final mode in MapMode.values)
                    AppListTile(
                      leading: Icon(mode.icon, color: brand),
                      title: mode.label,
                      subtitle: mode.description,
                      trailing: mode == _mode
                          ? Icon(
                              Icons.check_rounded,
                              color: brand,
                              semanticLabel: 'Selected',
                            )
                          : null,
                      onTap: () {
                        setState(() => _mode = mode);
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
              AppListGroup(
                title: 'EXTRAS',
                children: [
                  SwitchListTile(
                    value: _showFood,
                    title: const Text('Places to eat'),
                    subtitle: const Text('From OpenStreetMap, around the map'),
                    onChanged: (_) async {
                      final toggle = _toggleFood();
                      setSheetState(() {});
                      await toggle;
                    },
                  ),
                  if (aiReady)
                    AppListTile(
                      leading: Icon(Icons.auto_awesome_outlined, color: brand),
                      title: 'Suggest more places',
                      subtitle: 'Adds places near you to explore',
                      onTap: _isGenerating
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              _generateNearbyPlaces();
                            },
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  'WHAT THE PINS MEAN',
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              for (final (pin, meaning) in [
                (
                  MapPin.visited(icon: Icons.place_rounded, label: 'Example'),
                  'You\'ve been here',
                ),
                (
                  const MapPin(
                    icon: Icons.place_rounded,
                    color: AppTheme.primaryGreen,
                    label: 'Example',
                  ),
                  'Found nearby, not visited yet',
                ),
                (MapPin.saved(label: 'Example'), 'Saved to your wishlist'),
                (MapPin.unknown(), 'Unknown: get closer to reveal it'),
                (MapPin.food(label: 'Example'), 'Place to eat'),
                (MapPin.voice(label: 'Example'), 'Voice note left here'),
              ])
                Row(
                  children: [
                    ExcludeSemantics(child: pin),
                    const SizedBox(width: 12),
                    Expanded(child: Text(meaning, style: text.bodyMedium)),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
