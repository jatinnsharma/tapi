import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/service_area.dart';
import '../../core/services/firebase_status.dart';
import '../../core/services/ai_status.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../ai/application/ai_places_service.dart';
import '../auth/application/auth_service.dart';
import '../social/data/social_repository.dart';
import 'application/fog_service.dart';
import '../locations/data/location_community_repository.dart';
import '../locations/data/location_repository.dart';
import '../locations/domain/location.dart';
import '../locations/domain/location_tip.dart';
import '../locations/presentation/place_photo_gallery.dart';
import '../locations/presentation/place_sheet.dart';
import '../wishlist/application/wishlist_service.dart';
import '../wishlist/data/wishlist_repository.dart';
import '../wishlist/domain/wishlist_entry.dart';
import '../tracking/data/adventure_repository.dart';
import '../tracking/domain/route_point.dart';
import '../social/domain/footprint.dart';
import '../social/domain/friendship.dart';
import 'cached_tile_provider.dart';
import 'person_marker.dart';

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
  String get label {
    switch (this) {
      case MapMode.exploring:
        return 'Exploring';
      case MapMode.fullMap:
        return 'Full map';
      case MapMode.myPlaces:
        return 'My places';
      case MapMode.social:
        return 'Social map';
    }
  }

  IconData get icon {
    switch (this) {
      case MapMode.exploring:
        return Icons.visibility_off;
      case MapMode.fullMap:
        return Icons.visibility;
      case MapMode.myPlaces:
        return Icons.person_pin_circle;
      case MapMode.social:
        return Icons.group;
    }
  }
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
  LatLng? _currentLocation;
  List<ExploreLocation> _locations = [];
  bool _isLoading = true;
  bool _isGenerating = false;
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
      _locations = revealed;
      _isLoading = false;
    });
    unawaited(_syncNewlyDiscoveredBestEffort(allLocations, revealed));

    _locationSubscription = locationService.getLocationStream().listen(
      _onLocationUpdate,
    );
  }

  Future<void> _onLocationUpdate(LatLng position) async {
    final fogService = ref.read(fogServiceProvider);
    final previous = _locations;
    final revealed = await fogService.processPosition(position, previous);
    if (!mounted) return;
    setState(() {
      _currentLocation = position;
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
          content: Text('AI is not configured. Add GEMINI_API_KEY.'),
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
          content: Text('Discovered ${newLocations.length} new places!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate places: $e')));
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

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _centerOnUser() async {
    final locationService = ref.read(locationServiceProvider);
    final location = await locationService.getCurrentLocation();
    if (location != null) {
      setState(() => _currentLocation = location);
      _mapController.move(location, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                MetaPill(
                  icon: Icons.my_location,
                  label: 'Finding your location...',
                  background: Colors.white.withValues(alpha: 0.92),
                  foreground: AppTheme.forest,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_mode) {
          MapMode.myPlaces => 'My Map',
          MapMode.social => 'Social Map',
          _ => 'Map',
        }),
        actions: [
          if (_isGenerating)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _MapCircle(
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.forest,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: RoundIconButton(
                icon: Icons.auto_awesome,
                size: 42,
                tooltip: 'Discover Nearby Places with AI',
                onPressed: _generateNearbyPlaces,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 16),
            child: PopupMenuButton<MapMode>(
              tooltip: 'Map view',
              initialValue: _mode,
              color: Colors.white,
              elevation: 8,
              shadowColor: AppTheme.forest.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (mode) => setState(() => _mode = mode),
              itemBuilder: (context) => [
                for (final mode in MapMode.values)
                  PopupMenuItem(
                    value: mode,
                    child: Row(
                      children: [
                        Icon(
                          mode.icon,
                          size: 20,
                          color: mode == _mode
                              ? AppTheme.forest
                              : AppTheme.inkMuted,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: AppTheme.ink,
                            fontWeight: mode == _mode
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: _MapCircle(
                child: Icon(_mode.icon, color: AppTheme.forest, size: 21),
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
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.real_world_exploration',
                tileProvider: CachedTileProvider(),
              ),
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
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _showLocationSheet(location),
                        child: _buildMarkerIcon(
                          location,
                          isWishlisted: wishlistedLocationIds.contains(
                            location.id,
                          ),
                          isVisited: visitedIds.contains(location.id),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 16,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.forest.withValues(alpha: 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_mode.icon, size: 16, color: AppTheme.forest),
                    const SizedBox(width: 6),
                    Text(
                      _mode.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (visitedCount > 0)
            Positioned(
              bottom: 28,
              left: 16,
              child: IgnorePointer(
                child: MetaPill(
                  icon: Icons.check_circle,
                  label: '$visitedCount visited',
                  background: Colors.white.withValues(alpha: 0.94),
                  foreground: visitedColor,
                ),
              ),
            ),
          Positioned(
            bottom: 20,
            right: 20,
            child: RoundIconButton(
              icon: Icons.my_location,
              size: 54,
              tooltip: 'Center on my location',
              onPressed: _centerOnUser,
            ),
          ),
        ],
      ),
    );
  }

  /// Fill of the marker for places reached on a trip.
  static const Color visitedColor = AppTheme.emerald;

  Widget _buildMarkerIcon(
    ExploreLocation location, {
    required bool isWishlisted,
    required bool isVisited,
  }) {
    if (isVisited) {
      // Reached on a trip: a solid green disc with a gold tick, on every map
      // mode, so visited places stand out from everything else.
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: visitedColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.forest.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(location.category.icon, color: Colors.white, size: 18),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.amber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.check, size: 10, color: AppTheme.ink),
            ),
          ),
        ],
      );
    }
    if (location.isDiscovered) {
      return Icon(
        location.category.icon,
        color: location.category.color,
        size: 30,
      );
    }
    if (_mode == MapMode.myPlaces && isWishlisted) {
      return const Icon(Icons.bookmark, color: AppTheme.amber, size: 30);
    }
    return Opacity(
      opacity: 0.4,
      child: Icon(Icons.help_outline, color: location.category.color, size: 30),
    );
  }

  void _showLocationSheet(ExploreLocation location) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photos only once discovered: undiscovered places stay hidden.
            if (location.isDiscovered) ...[
              PlacePhotoGallery(place: location, height: 180),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Icon(
                  location.isDiscovered
                      ? location.category.icon
                      : Icons.help_outline,
                  color: location.category.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location.isDiscovered
                        ? location.name
                        : 'Undiscovered location',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (location.isDiscovered) ...[
              Text(
                location.description,
                style: const TextStyle(color: AppTheme.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MetaPill(
                    label: location.category.label,
                    background: AppTheme.primaryGreen.withValues(alpha: 0.12),
                    foreground: AppTheme.forest,
                  ),
                  MetaPill(
                    icon: Icons.bolt_rounded,
                    label: '+${location.xpReward} XP',
                    background: AppTheme.amber,
                    foreground: AppTheme.ink,
                  ),
                ],
              ),
            ] else
              const Text(
                'Get closer to reveal this location.',
                style: TextStyle(color: AppTheme.inkMuted),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Undiscovered places stay unnamed until you get there.
                  startTripToPlace(
                    this.context,
                    ref,
                    location,
                    displayName: location.isDiscovered
                        ? null
                        : 'Undiscovered location',
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(location.isDiscovered ? 'Start' : 'Guide me there'),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Consumer(
              builder: (context, ref, _) {
                final keysAsync = ref.watch(wishlistKeysProvider);
                final saved = keysAsync.maybeWhen(
                  data: (keys) =>
                      isWishlisted(keys, WishlistType.location, location.id),
                  orElse: () => false,
                );
                return OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    await ref
                        .read(wishlistRepositoryProvider)
                        .toggle(WishlistType.location, location.id);
                    ref.invalidate(wishlistKeysProvider);
                  },
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
                  label: Text(saved ? 'Saved to wishlist' : 'Save to wishlist'),
                );
              },
            ),
            if (location.isDiscovered) ...[
              const SizedBox(height: 16),
              const Divider(),
              _LocationCommunitySection(location: location),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationCommunitySection extends ConsumerStatefulWidget {
  const _LocationCommunitySection({required this.location});

  final ExploreLocation location;

  @override
  ConsumerState<_LocationCommunitySection> createState() =>
      _LocationCommunitySectionState();
}

class _LocationCommunitySectionState
    extends ConsumerState<_LocationCommunitySection> {
  late Future<(int, List<LocationTip>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(int, List<LocationTip>)> _load() async {
    final repository = ref.read(locationCommunityRepositoryProvider);
    final count = await repository.getExplorerCount(widget.location.id);
    final tips = await repository.getTips(widget.location.id);
    return (count, tips);
  }

  @override
  Widget build(BuildContext context) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    if (!firebaseReady) return const SizedBox.shrink();

    return FutureBuilder<(int, List<LocationTip>)>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Shimmer(child: SkeletonBox(height: 44, radius: 16)),
          );
        }
        final (count, tips) = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.people_outline,
                  size: 18,
                  color: AppTheme.forest,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count explorer${count == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddTipDialog(context),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('Add Tip'),
                ),
              ],
            ),
            if (tips.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final tip in tips.take(5))
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${tip.displayName}: ',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: tip.text),
                      ],
                    ),
                    style: const TextStyle(color: AppTheme.ink, height: 1.35),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  void _showAddTipDialog(BuildContext context) {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to share a tip.')));
      return;
    }

    final textController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share a Tip'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'e.g. Best visited at sunrise',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: () async {
              if (textController.text.trim().isEmpty) return;
              final profile = await ref
                  .read(socialRepositoryProvider)
                  .getProfile(user.uid);
              await ref
                  .read(locationCommunityRepositoryProvider)
                  .postTip(
                    widget.location.id,
                    LocationTip(
                      id: '',
                      uid: user.uid,
                      displayName:
                          profile?.displayName ??
                          user.email?.split('@').first ??
                          'Explorer',
                      text: textController.text.trim(),
                      timestamp: DateTime.now(),
                    ),
                  );
              if (context.mounted) Navigator.of(context).pop();
              setState(() => _future = _load());
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

/// Round white surface matching [RoundIconButton], for app bar actions that
/// need a custom child (spinner, popup menu trigger).
class _MapCircle extends StatelessWidget {
  const _MapCircle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.forest.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
