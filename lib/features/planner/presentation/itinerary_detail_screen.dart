import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../locations/presentation/place_photo_gallery.dart';
import '../../tracking/data/directions_service.dart';
import '../data/opening_hours_service.dart';
import '../data/saved_trips_repository.dart';
import '../data/trip_planner_service.dart';
import '../domain/opening_hours.dart';
import '../domain/trip_plan.dart';
import 'stop_actions.dart';
import 'stop_hours.dart';
import 'trip_essentials_view.dart';
import 'trip_share.dart';

/// Road route through a day's stops, keyed by their positions
/// ("lat,lng;lat,lng;..."). Null when it can't be fetched (offline); the map
/// then falls back to straight lines. Kept for the session, so switching
/// days doesn't refetch.
final _dayRouteProvider = FutureProvider.autoDispose
    .family<MultiStopRoute?, String>((ref, key) async {
      final points = [
        for (final pair in key.split(';'))
          LatLng(
            double.parse(pair.split(',')[0]),
            double.parse(pair.split(',')[1]),
          ),
      ];
      try {
        final route = await ref
            .read(directionsServiceProvider)
            .routeThrough(points);
        ref.keepAlive();
        return route;
      } catch (_) {
        return null;
      }
    });

String _routeKey(List<TripStop> stops) => stops
    .map(
      (s) =>
          '${s.latitude.toStringAsFixed(5)},${s.longitude.toStringAsFixed(5)}',
    )
    .join(';');

class ItineraryDetailScreen extends ConsumerStatefulWidget {
  const ItineraryDetailScreen({
    super.key,
    required this.plan,
    this.initialDayIndex = 0,
  });

  final TripPlan plan;

  /// The day tab to open on (0 = Day 1), e.g. today's day of the trip.
  final int initialDayIndex;

  @override
  ConsumerState<ItineraryDetailScreen> createState() =>
      _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends ConsumerState<ItineraryDetailScreen> {
  late TripPlan _plan;
  late int _selectedDayIndex = widget.initialDayIndex.clamp(
    0,
    widget.plan.days.length,
  );
  bool _isRegenerating = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
  }

  /// The tab after the last day shows the trip's essentials.
  bool get _showingEssentials => _selectedDayIndex >= _plan.days.length;

  TripDayPlan get _currentDay => _plan.days[_selectedDayIndex];

  /// Shows and saves a change made on this phone.
  void _commit(TripPlan updated) {
    final stamped = updated.copyWith(updatedAt: DateTime.now());
    setState(() => _plan = stamped);
    ref.read(savedTripsListProvider.notifier).updatePlan(stamped);
  }

  void _selectTab(int index) {
    setState(() => _selectedDayIndex = index);
    if (_showingEssentials) return;
    final stops = _plan.days[index].stops;
    if (stops.isNotEmpty) {
      // The map is rebuilt for the new day after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _showingEssentials) return;
        try {
          _mapController.move(stops.first.coordinates, 13);
        } catch (_) {}
      });
    }
  }

  Future<void> _regenerateCurrentDay() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Regenerate Day ${_currentDay.dayNumber}?'),
        content: const Text(
          'This will generate new stops, activities, and dining ideas for this day while keeping the rest of your trip unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRegenerating = true);

    try {
      final service = ref.read(tripPlannerServiceProvider);
      final newDay = await service.regenerateDay(
        currentPlan: _plan,
        dayNumber: _currentDay.dayNumber,
      );

      final updatedDays = List<TripDayPlan>.from(_plan.days);
      updatedDays[_selectedDayIndex] = newDay;

      _commit(_plan.copyWith(days: updatedDays));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Day ${newDay.dayNumber} regenerated successfully!'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not regenerate day. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  void _moveStop(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= _currentDay.stops.length) return;
    final stops = List<TripStop>.from(_currentDay.stops);
    final stop = stops.removeAt(oldIndex);
    stops.insert(newIndex, stop);

    final updatedDay = _currentDay.copyWith(stops: stops);
    final updatedDays = List<TripDayPlan>.from(_plan.days);
    updatedDays[_selectedDayIndex] = updatedDay;

    _commit(_plan.copyWith(days: updatedDays));
  }

  void _deleteStop(int index) {
    final stops = List<TripStop>.from(_currentDay.stops)..removeAt(index);
    final updatedDay = _currentDay.copyWith(stops: stops);
    final updatedDays = List<TripDayPlan>.from(_plan.days);
    updatedDays[_selectedDayIndex] = updatedDay;

    _commit(_plan.copyWith(days: updatedDays));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop removed from itinerary')),
    );
  }

  Future<void> _shareTrip(String how) async {
    if (how == 'image') {
      await showTripImageShare(context, _plan);
      return;
    }
    try {
      await shareTripAsText(_plan);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet.')),
      );
    }
  }

  /// The first stop of the current day not done yet, or null when all are.
  int? get _nextStopIndex {
    final i = _currentDay.stops.indexWhere((s) => !s.isCompleted);
    return i < 0 ? null : i;
  }

  void _setStopCompleted(int dayIndex, int stopIndex, bool done) {
    final day = _plan.days[dayIndex];
    final stops = List<TripStop>.from(day.stops);
    stops[stopIndex] = stops[stopIndex].copyWith(isCompleted: done);
    final updatedDays = List<TripDayPlan>.from(_plan.days);
    updatedDays[dayIndex] = day.copyWith(stops: stops);
    _commit(_plan.copyWith(days: updatedDays));
  }

  /// Starts a tracked trip to one stop. Its place id goes with it, so
  /// arriving (confirmed with the live photo, as for any place) counts as
  /// visiting that place, pays its XP and marks the stop done here.
  Future<void> _goToStop(int stopIndex) async {
    final dayIndex = _selectedDayIndex;
    final day = _plan.days[dayIndex];
    final stop = day.stops[stopIndex];
    final reached = await goToStop(context, ref, _plan, dayIndex, stopIndex);
    if (!mounted || !reached) return;
    final now = _plan.days[dayIndex].stops.indexWhere((s) => s.id == stop.id);
    if (now < 0 || _plan.days[dayIndex].stops[now].isCompleted) return;
    _setStopCompleted(dayIndex, now, true);

    final next = _nextStopIndex;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next == null || _selectedDayIndex != dayIndex
              ? '${stop.placeName} done. Day ${day.dayNumber} complete!'
              : '${stop.placeName} done. Next: ${_currentDay.stops[next].placeName}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A shared trip can change on a friend's phone while it's open here.
    if (_plan.isShared) {
      ref.listen(cloudTripProvider(_plan.id), (_, next) {
        final remote = next.value;
        if (remote == null || !remote.lastChanged.isAfter(_plan.lastChanged)) {
          return;
        }
        setState(() {
          _plan = remote;
          if (_selectedDayIndex > _plan.days.length) {
            _selectedDayIndex = _plan.days.length;
          }
        });
        ref.read(savedTripsListProvider.notifier).applyRemote(remote);
      });
    }

    final stops = _showingEssentials ? const <TripStop>[] : _currentDay.stops;
    final mapCenter = stops.isNotEmpty
        ? LatLng(stops.first.latitude, stops.first.longitude)
        : const LatLng(28.6139, 77.2090);
    final route = stops.length > 1
        ? ref.watch(_dayRouteProvider(_routeKey(stops))).value
        : null;
    final hasRoadPath = route != null && route.path.length > 1;
    final nextStop = _showingEssentials ? null : _nextStopIndex;

    // Opening hours for the day's stops: OpenStreetMap's, else the AI's
    // estimate.
    final hoursAsync = stops.isEmpty
        ? null
        : ref.watch(
            dayOpeningHoursProvider(
              encodeHoursQueries([
                for (final s in stops)
                  (
                    key: s.id,
                    placeId: s.placeId,
                    name: s.placeName,
                    lat: s.latitude,
                    lng: s.longitude,
                  ),
              ]),
            ),
          );
    final mapHours = hoursAsync?.value ?? const <String, String>{};
    ({OpeningHours? hours, HoursSource? source}) hoursOf(TripStop s) {
      final fromMap = OpeningHours.parse(mapHours[s.id]);
      if (fromMap != null) return (hours: fromMap, source: HoursSource.map);
      final fromAi = OpeningHours.parse(s.openingHours);
      if (fromAi != null) return (hours: fromAi, source: HoursSource.ai);
      return (hours: null, source: null);
    }

    final plannedDay = _showingEssentials || _plan.startDate == null
        ? null
        : DateUtils.dateOnly(_plan.startDate!)
              .add(Duration(days: _currentDay.dayNumber - 1));
    final closedStops = [
      for (final s in stops)
        if (!s.isCompleted &&
            verdictFor(hoursOf(s).hours, plannedDay, s.timeSlot) ==
                HoursVerdict.closedThatDay)
          s.placeName,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_plan.destination),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share itinerary',
            onSelected: _shareTrip,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'text',
                child: ListTile(
                  leading: Icon(Icons.notes),
                  title: Text('Share as text'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'image',
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Share as image'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              _plan.cloudSynced ? Icons.cloud_done_outlined : Icons.bookmark,
            ),
            color: AppTheme.amber,
            tooltip: _plan.cloudSynced ? 'Backed up' : 'Saved on this phone',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _plan.cloudSynced
                        ? 'Saved in My Trips and backed up to your account'
                        : 'Saved in My Trips on this phone. Sign in to back it up.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Day Tabs
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.white.withValues(alpha: 0.8),
              child: SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _plan.days.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final isSelected = _selectedDayIndex == idx;
                    final isEssentials = idx == _plan.days.length;
                    return ChoiceChip(
                      avatar: isEssentials
                          ? Icon(
                              Icons.luggage_outlined,
                              size: 18,
                              color: isSelected ? Colors.white : AppTheme.ink,
                            )
                          : null,
                      label: Text(
                        isEssentials ? 'Essentials' : 'Day ${idx + 1}',
                      ),
                      selected: isSelected,
                      onSelected: (_) => _selectTab(idx),
                      selectedColor: AppTheme.forest,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.ink,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                      backgroundColor: Colors.white,
                    );
                  },
                ),
              ),
            ),

            // Scrollable day details
            Expanded(
              child: _showingEssentials
                  ? TripEssentialsView(
                      plan: _plan,
                      onEdit: _commit,
                      onStored: (stored) => setState(() => _plan = stored),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      children: [
                        // Day Title & Theme
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Day ${_currentDay.dayNumber}: ${_currentDay.title}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  if (_currentDay.theme != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      _currentDay.theme!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.inkMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton.outlined(
                              icon: _isRegenerating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh, size: 20),
                              tooltip: 'Regenerate this day',
                              onPressed: _isRegenerating
                                  ? null
                                  : _regenerateCurrentDay,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Route Map for this Day
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            height: 190,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: mapCenter,
                                initialZoom: 12.8,
                                interactionOptions: const InteractionOptions(
                                  flags:
                                      InteractiveFlag.all &
                                      ~InteractiveFlag.rotate,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.example.real_world_exploration',
                                ),
                                if (stops.length > 1)
                                  PolylineLayer(
                                    polylines: [
                                      // The road route when we have it;
                                      // otherwise dotted straight lines,
                                      // which only show the order.
                                      Polyline(
                                        points: hasRoadPath
                                            ? route.path
                                            : [
                                                for (final s in stops)
                                                  s.coordinates,
                                              ],
                                        color: AppTheme.forest,
                                        strokeWidth: 4.0,
                                        pattern: hasRoadPath
                                            ? const StrokePattern.solid()
                                            : StrokePattern.dotted(),
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    for (var i = 0; i < stops.length; i++)
                                      Marker(
                                        point: LatLng(
                                          stops[i].latitude,
                                          stops[i].longitude,
                                        ),
                                        width: 32,
                                        height: 32,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: stops[i].isCompleted
                                                ? Colors.grey
                                                : i == nextStop
                                                ? AppTheme.primary
                                                : AppTheme.forest,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: stops[i].isCompleted
                                                ? const Icon(
                                                    Icons.check,
                                                    size: 16,
                                                    color: Colors.white,
                                                  )
                                                : Text(
                                                    '${i + 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // A stop that's closed on this day of the week.
                        if (closedStops.isNotEmpty && plannedDay != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCE8E6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.event_busy_rounded,
                                  color: Color(0xFFD93025),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${closedStops.join(', ')} '
                                    '${closedStops.length == 1 ? 'is' : 'are'} closed on '
                                    '${DateFormat('EEEE').format(plannedDay)}s. '
                                    'Swap ${closedStops.length == 1 ? 'it' : 'them'} with another day, or regenerate this day.',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Day Local Tip Card
                        if (_currentDay.dayTip != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppTheme.amber.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline,
                                  color: AppTheme.amberText,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _currentDay.dayTip!,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.ink,
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),

                        // Stops Header
                        Row(
                          children: [
                            Text(
                              'Planned Stops (${stops.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.ink,
                              ),
                            ),
                            const Spacer(),
                            if (stops.any((s) => s.isCompleted))
                              Text(
                                '${stops.where((s) => s.isCompleted).length} of ${stops.length} done',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Stops List
                        if (stops.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No stops for this day. Tap regenerate to add sights!',
                                style: TextStyle(color: AppTheme.inkMuted),
                              ),
                            ),
                          )
                        else
                          ...List.generate(stops.length, (idx) {
                            final stop = stops[idx];
                            final leg =
                                idx > 0 &&
                                    route != null &&
                                    idx - 1 < route.legs.length
                                ? describeLeg(route.legs[idx - 1])
                                : idx > 0
                                ? stop.travelTimeFromPrevious
                                : null;
                            final legIcon =
                                route != null &&
                                    idx > 0 &&
                                    idx - 1 < route.legs.length &&
                                    route.legs[idx - 1].meters <=
                                        walkableLegMeters
                                ? Icons.directions_walk
                                : Icons.local_taxi_outlined;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (leg != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      0,
                                      10,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          legIcon,
                                          size: 16,
                                          color: AppTheme.inkMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            leg,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.inkMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Opacity(
                                    opacity: stop.isCompleted ? 0.7 : 1,
                                    child: SoftCard(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Photos of the place; tap one
                                          // for full screen.
                                          PlacePhotoGallery(
                                            key: ValueKey('photos-${stop.id}'),
                                            place: stopAsPlace(
                                              stop,
                                              _plan.destination,
                                            ),
                                            height: 150,
                                            radius: 16,
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  color: stop.isCompleted
                                                      ? AppTheme.primary
                                                      : AppTheme.forest,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: stop.isCompleted
                                                      ? const Icon(
                                                          Icons.check,
                                                          size: 15,
                                                          color: Colors.white,
                                                        )
                                                      : Text(
                                                          '${idx + 1}',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  stop.timeSlot.toUpperCase(),
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppTheme.primary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${stop.durationMinutes} min',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.inkMuted,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const Spacer(),
                                              // Reorder & Delete actions
                                              if (idx > 0)
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.arrow_upward,
                                                    size: 18,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(),
                                                  tooltip: 'Move up',
                                                  onPressed: () =>
                                                      _moveStop(idx, idx - 1),
                                                ),
                                              if (idx < stops.length - 1) ...[
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.arrow_downward,
                                                    size: 18,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(),
                                                  tooltip: 'Move down',
                                                  onPressed: () =>
                                                      _moveStop(idx, idx + 1),
                                                ),
                                              ],
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                  color: Colors.grey,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                tooltip: 'Remove stop',
                                                onPressed: () =>
                                                    _deleteStop(idx),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            stop.placeName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          StopHours(
                                            key: ValueKey('hours-${stop.id}'),
                                            hours: hoursOf(stop).hours,
                                            source: hoursOf(stop).source,
                                            loading:
                                                hoursAsync?.isLoading ?? false,
                                            plannedDay: plannedDay,
                                            timeSlot: stop.timeSlot,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            stop.description,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.ink,
                                              height: 1.35,
                                            ),
                                          ),
                                          if (stop.tip != null) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .tips_and_updates_outlined,
                                                  size: 15,
                                                  color: AppTheme.amberText,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    stop.tip!,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme.amberText,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              TextButton.icon(
                                                icon: const Icon(
                                                  Icons.navigation_outlined,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  '+${stop.xpReward ?? TripStop.defaultXp} XP · Go',
                                                ),
                                                onPressed: () => _goToStop(idx),
                                              ),
                                              const Spacer(),
                                              TextButton.icon(
                                                icon: Icon(
                                                  stop.isCompleted
                                                      ? Icons.undo
                                                      : Icons
                                                            .check_circle_outline,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  stop.isCompleted
                                                      ? 'Undo'
                                                      : 'Mark done',
                                                ),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      AppTheme.inkMuted,
                                                ),
                                                onPressed: () =>
                                                    _setStopCompleted(
                                                      _selectedDayIndex,
                                                      idx,
                                                      !stop.isCompleted,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),

                        // Food suggestions
                        if (_currentDay.foodSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Recommended Food & Cafes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _currentDay.foodSuggestions.map((food) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.restaurant_menu,
                                        size: 16,
                                        color: AppTheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          food,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.ink,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      // Sticky bottom action
      bottomSheet: _showingEssentials
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: Icon(
                    nextStop == null && stops.isNotEmpty
                        ? Icons.celebration_rounded
                        : Icons.navigation_rounded,
                    size: 20,
                  ),
                  label: Text(
                    stops.isEmpty
                        ? 'No stops planned for this day'
                        : nextStop == null
                        ? 'Day ${_currentDay.dayNumber} complete!'
                        : 'Go to stop ${nextStop + 1}: ${stops[nextStop].placeName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.forest,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.sage,
                    disabledForegroundColor: AppTheme.forest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: nextStop == null
                      ? null
                      : () => _goToStop(nextStop),
                ),
              ),
            ),
    );
  }
}
