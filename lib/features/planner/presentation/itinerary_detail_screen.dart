import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/ui/friendly_error.dart';
import '../domain/safety_tips.dart';
import '../../locations/presentation/place_photo_gallery.dart';
import '../../tracking/data/directions_service.dart';
import '../data/opening_hours_service.dart';
import '../data/saved_trips_repository.dart';
import '../data/trip_planner_service.dart';
import '../domain/opening_hours.dart';
import '../domain/trip_plan.dart';
import 'stop_actions.dart';
import 'stop_number_badge.dart';
import 'stop_hours.dart';
import 'trip_essentials_view.dart';
import 'trip_share.dart';
import '../../map/osm_tiles.dart';
import 'rebalance_sheet.dart';
import '../../tours/presentation/publish_tour.dart';
import '../../../core/ui/confirm_destructive.dart';

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
  late int _selectedDayIndex = _clampDay(widget.initialDayIndex);
  bool _isRegenerating = false;
  final MapController _mapController = MapController();

  /// Plan (the days) or Essentials (dates, weather, budget, packing).
  /// `?day=N` one past the last day opens Essentials, as before.
  late bool _essentials = widget.initialDayIndex >= widget.plan.days.length;

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
  }

  int _clampDay(int index) =>
      index.clamp(0, (widget.plan.days.length - 1).clamp(0, 1 << 20));

  /// A plan with no days only has essentials.
  bool get _showingEssentials => _essentials || _plan.days.isEmpty;

  TripDayPlan get _currentDay => _plan.days[_selectedDayIndex];

  /// Shows and saves a change made on this phone.
  void _commit(TripPlan updated) {
    final stamped = updated.copyWith(updatedAt: DateTime.now());
    setState(() => _plan = stamped);
    ref.read(savedTripsListProvider.notifier).updatePlan(stamped);
  }

  void _selectDay(int index) {
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

  /// Re-plans the rest of the day (running late, tired, a place closed,
  /// rain), with Undo.
  Future<void> _adjustDay() async {
    final before = _plan;
    final updated = await showRebalanceSheet(
      context,
      ref,
      _plan,
      _selectedDayIndex,
    );
    if (updated == null || !mounted) return;
    _commit(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Day adjusted.'),
        action: SnackBarAction(label: 'Undo', onPressed: () => _commit(before)),
      ),
    );
  }

  Future<void> _regenerateCurrentDay() async {
    final dayNumber = _currentDay.dayNumber;
    // An empty day has nothing to lose: no need to ask.
    if (_currentDay.stops.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Replan Day $dayNumber?'),
          content: const Text(
            'You\'ll get new stops and food ideas for this day. Other days '
            'stay the same, and you can undo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replan day'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    final before = _plan;

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
      showUndoSnackBar(
        context,
        message: 'Day ${newDay.dayNumber} replanned',
        onUndo: () => _commit(before),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t replan the day. ${friendlyError(e)}'),
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
    final before = _plan;
    final removed = _currentDay.stops[index];
    final stops = List<TripStop>.from(_currentDay.stops)..removeAt(index);
    final updatedDay = _currentDay.copyWith(stops: stops);
    final updatedDays = List<TripDayPlan>.from(_plan.days);
    updatedDays[_selectedDayIndex] = updatedDay;

    _commit(_plan.copyWith(days: updatedDays));

    showUndoSnackBar(
      context,
      message: '${removed.placeName} removed',
      onUndo: () => _commit(before),
    );
  }

  Future<void> _shareTrip(String how) async {
    if (how == 'tour') {
      await publishDayAsTour(context, ref, _plan, _selectedDayIndex);
      return;
    }
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

    final next = _selectedDayIndex == dayIndex ? _nextStopIndex : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          next == null
              ? '${stop.placeName} done. Day ${day.dayNumber} complete!'
              : '${stop.placeName} done. Next: ${_currentDay.stops[next].placeName}',
        ),
        // Keeps the day moving: one tap starts the trip to the next stop.
        action: next == null
            ? null
            : SnackBarAction(label: 'Go', onPressed: () => _goToStop(next)),
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
          if (_selectedDayIndex >= _plan.days.length) {
            _selectedDayIndex = (_plan.days.length - 1).clamp(0, 1 << 20);
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

    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final doneCount = stops.where((s) => s.isCompleted).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_plan.destination),
        actions: [
          AppIconButton(
            icon: Icons.photo_library_outlined,
            tooltip: 'Trip album',
            onPressed: () => context.push('/trips/${_plan.id}/album'),
          ),
          AppIconButton(
            icon: Icons.share_outlined,
            tooltip: 'Share trip',
            onPressed: _showShareSheet,
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              if (!_showingEssentials && _nextStopIndex != null)
                PopupMenuItem(
                  value: _adjustDay,
                  child: const ListTile(
                    leading: Icon(Icons.update_rounded),
                    title: Text('Running late? Adjust the day'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!_showingEssentials)
                PopupMenuItem(
                  value: _regenerateCurrentDay,
                  enabled: !_isRegenerating,
                  child: const ListTile(
                    leading: Icon(Icons.autorenew_rounded),
                    title: Text('Replan this day'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: () => showSafetyTipsModal(context),
                child: const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Safety & helplines'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SyncLine(plan: _plan),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Plan'),
                        icon: Icon(Icons.route_outlined),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Essentials'),
                        icon: Icon(Icons.luggage_outlined),
                      ),
                    ],
                    selected: {_showingEssentials},
                    onSelectionChanged: _plan.days.isEmpty
                        ? null
                        : (v) => setState(() => _essentials = v.single),
                  ),
                ],
              ),
            ),
            if (!_showingEssentials)
              _DaySelector(
                plan: _plan,
                selected: _selectedDayIndex,
                onSelected: _selectDay,
              ),
            Expanded(
              child: _showingEssentials
                  ? TripEssentialsView(
                      plan: _plan,
                      onEdit: _commit,
                      onStored: (stored) => setState(() => _plan = stored),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Text(_currentDay.title, style: text.titleLarge),
                        if (_currentDay.theme != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _currentDay.theme!,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        if (stops.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${stops.length} stops'
                            '${doneCount > 0 ? ' · $doneCount done' : ''}',
                            style: text.labelMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (stops.isNotEmpty)
                          _DayMap(
                            stops: stops,
                            route: hasRoadPath ? route.path : null,
                            nextStop: nextStop,
                            controller: _mapController,
                            initialCenter: mapCenter,
                            onExpand: () => _openFullMap(
                              stops,
                              hasRoadPath ? route.path : null,
                              nextStop,
                            ),
                          ),
                        const SizedBox(height: 12),
                        // A stop that's closed on this day of the week.
                        if (closedStops.isNotEmpty && plannedDay != null) ...[
                          StatusBanner(
                            kind: StatusKind.warning,
                            title:
                                '${closedStops.join(', ')} '
                                '${closedStops.length == 1 ? 'is' : 'are'} '
                                'closed on '
                                '${DateFormat('EEEE').format(plannedDay)}s',
                            message:
                                'Move ${closedStops.length == 1 ? 'it' : 'them'} '
                                'to another day, or replan this day.',
                            actionLabel: 'Replan day',
                            onAction: _regenerateCurrentDay,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_currentDay.dayTip != null) ...[
                          StatusBanner(
                            kind: StatusKind.info,
                            title: 'Local tip',
                            message: _currentDay.dayTip,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (stops.isEmpty)
                          GateCard(
                            icon: Icons.event_note_outlined,
                            title: 'Nothing planned for this day',
                            message: 'Let the planner suggest stops for it.',
                            actionLabel: 'Plan this day',
                            onAction: _regenerateCurrentDay,
                          )
                        else
                          for (var idx = 0; idx < stops.length; idx++) ...[
                            if (idx > 0)
                              _LegRow(
                                label:
                                    route != null && idx - 1 < route.legs.length
                                    ? describeLeg(route.legs[idx - 1])
                                    : stops[idx].travelTimeFromPrevious,
                                walk:
                                    route != null &&
                                    idx - 1 < route.legs.length &&
                                    route.legs[idx - 1].meters <=
                                        walkableLegMeters,
                              ),
                            _StopRow(
                              key: ValueKey('stop-${stops[idx].id}'),
                              number: idx + 1,
                              stop: stops[idx],
                              isNext: idx == nextStop,
                              verdict: verdictFor(
                                hoursOf(stops[idx]).hours,
                                plannedDay,
                                stops[idx].timeSlot,
                              ),
                              onTap: () => _showStop(
                                idx,
                                hours: hoursOf(stops[idx]),
                                loadingHours: hoursAsync?.isLoading ?? false,
                                plannedDay: plannedDay,
                              ),
                            ),
                          ],
                        if (_currentDay.foodSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('Places to eat', style: text.titleMedium),
                          const SizedBox(height: 8),
                          for (final food in _currentDay.foodSuggestions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.restaurant_menu,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(food, style: text.bodyMedium),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      // The one main action: go to the next stop.
      bottomNavigationBar: _showingEssentials || stops.isEmpty
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: nextStop == null
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.celebration_rounded,
                              color: colors.success,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Day ${_currentDay.dayNumber} done',
                              style: text.titleMedium,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '+${stops[nextStop].xpReward ?? TripStop.defaultXp} '
                              'XP when you get there',
                              style: text.labelMedium?.copyWith(
                                color: colors.rewardText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppButton(
                              label:
                                  'Go to stop ${nextStop + 1}: '
                                  '${stops[nextStop].placeName}',
                              icon: Icons.navigation_rounded,
                              expand: true,
                              onPressed: () => _goToStop(nextStop),
                            ),
                          ],
                        ),
                ),
              ),
            ),
    );
  }

  void _showShareSheet() {
    showAppSheet<void>(
      context,
      title: 'Share trip',
      body: Column(
        children: [
          for (final (how, icon, label, detail) in [
            ('text', Icons.notes, 'As text', 'The plan in a message'),
            (
              'image',
              Icons.image_outlined,
              'As an image',
              'A picture of the plan',
            ),
            if (!_showingEssentials)
              (
                'tour',
                Icons.tour_outlined,
                'Publish Day ${_currentDay.dayNumber} as a tour',
                'Others can follow your route',
              ),
          ])
            Builder(
              builder: (sheetContext) => AppListTile(
                leading: Icon(icon),
                title: label,
                subtitle: detail,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _shareTrip(how);
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openFullMap(List<TripStop> stops, List<LatLng>? path, int? nextStop) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Day ${_currentDay.dayNumber}')),
          body: _DayMapView(
            stops: stops,
            route: path,
            nextStop: nextStop,
            interactive: true,
            initialCenter: stops.first.coordinates,
          ),
        ),
      ),
    );
  }

  /// A stop's details and its edits (done, order, remove) in one sheet.
  void _showStop(
    int index, {
    required ({OpeningHours? hours, HoursSource? source}) hours,
    required bool loadingHours,
    required DateTime? plannedDay,
  }) {
    final dayIndex = _selectedDayIndex;
    final stop = _currentDay.stops[index];
    final count = _currentDay.stops.length;
    showAppSheet<void>(
      context,
      title: stop.placeName,
      body: Builder(
        builder: (sheetContext) {
          final text = Theme.of(sheetContext).textTheme;
          final colors = AppColors.of(sheetContext);
          void then(VoidCallback action) {
            Navigator.of(sheetContext).pop();
            action();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlacePhotoGallery(
                key: ValueKey('photos-${stop.id}'),
                place: stopAsPlace(stop, _plan.destination),
                height: 180,
                radius: AppRadius.md,
              ),
              const SizedBox(height: 12),
              Text(
                '${stop.timeSlot} · ${stop.durationMinutes} min',
                style: text.labelLarge?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 4),
              StopHours(
                key: ValueKey('hours-${stop.id}'),
                hours: hours.hours,
                source: hours.source,
                loading: loadingHours,
                plannedDay: plannedDay,
                timeSlot: stop.timeSlot,
              ),
              const SizedBox(height: 8),
              Text(stop.description, style: text.bodyLarge),
              if (stop.tip != null) ...[
                const SizedBox(height: 12),
                StatusBanner(
                  kind: StatusKind.info,
                  title: 'Tip',
                  message: stop.tip,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  AppButton.tertiary(
                    label: stop.isCompleted ? 'Mark not done' : 'Mark done',
                    icon: stop.isCompleted
                        ? Icons.undo_rounded
                        : Icons.check_circle_outline,
                    onPressed: () => then(
                      () =>
                          _setStopCompleted(dayIndex, index, !stop.isCompleted),
                    ),
                  ),
                  if (index > 0)
                    AppButton.tertiary(
                      label: 'Move earlier',
                      icon: Icons.arrow_upward_rounded,
                      onPressed: () => then(() => _moveStop(index, index - 1)),
                    ),
                  if (index < count - 1)
                    AppButton.tertiary(
                      label: 'Move later',
                      icon: Icons.arrow_downward_rounded,
                      onPressed: () => then(() => _moveStop(index, index + 1)),
                    ),
                  AppButton.tertiary(
                    label: 'Remove',
                    icon: Icons.delete_outline_rounded,
                    onPressed: () => then(() => _deleteStop(index)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      action: Builder(
        builder: (sheetContext) => AppButton(
          label: 'Go here · +${stop.xpReward ?? TripStop.defaultXp} XP',
          icon: Icons.navigation_rounded,
          expand: true,
          onPressed: () {
            Navigator.of(sheetContext).pop();
            _goToStop(index);
          },
        ),
      ),
    );
  }
}

/// "Saved on this phone" or "Backed up": a quiet status, not a button.
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.plan});

  final TripPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final synced = plan.cloudSynced;
    return Row(
      children: [
        Icon(
          synced ? Icons.cloud_done_outlined : Icons.smartphone_outlined,
          size: 16,
          color: colors.textSecondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            synced ? 'Backed up' : 'Saved on this phone',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Day 1 · Day 2 …, with the date under each when the trip has dates.
class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.plan,
    required this.selected,
    required this.onSelected,
  });

  final TripPlan plan;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final start = plan.startDate;
    final dateFormat = DateFormat('d MMM');
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: plan.days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final date = start == null
              ? null
              : DateUtils.dateOnly(start).add(Duration(days: i));
          return ChoiceChip(
            label: Text(
              date == null
                  ? 'Day ${i + 1}'
                  : 'Day ${i + 1} · ${dateFormat.format(date)}',
            ),
            selected: i == selected,
            onSelected: (_) => onSelected(i),
          );
        },
      ),
    );
  }
}

/// The travel time between two stops, in the gap between their rows.
class _LegRow extends StatelessWidget {
  const _LegRow({required this.label, required this.walk});

  final String? label;
  final bool walk;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final leg = label;
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Row(
        children: [
          Container(width: 2, height: 28, color: colors.border),
          const SizedBox(width: 18),
          if (leg != null) ...[
            Icon(
              walk ? Icons.directions_walk : Icons.local_taxi_outlined,
              size: 16,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                leg,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One stop in the day's timeline: number, name, when and for how long,
/// and whether it's open then. Tap for details and edits.
class _StopRow extends StatelessWidget {
  const _StopRow({
    super.key,
    required this.number,
    required this.stop,
    required this.isNext,
    required this.verdict,
    required this.onTap,
  });

  final int number;
  final TripStop stop;
  final bool isNext;
  final HoursVerdict verdict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hoursNote = switch (verdict) {
      HoursVerdict.closedThatDay => 'Closed that day',
      HoursVerdict.wrongTime => 'May be closed then',
      _ => null,
    };
    return Semantics(
      button: true,
      label:
          'Stop $number, ${stop.placeName}, ${stop.timeSlot}'
          '${stop.isCompleted ? ', done' : ''}'
          '${isNext ? ', next' : ''}'
          '${hoursNote == null ? '' : ', $hoursNote'}',
      excludeSemantics: true,
      child: Material(
        color: isNext ? scheme.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: isNext ? scheme.primary : colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  StopNumberBadge(number: number, done: stop.isCompleted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.placeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            decoration: stop.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${stop.timeSlot} · ${stop.durationMinutes} min',
                          style: text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (hoursNote != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.event_busy_rounded,
                                size: 14,
                                color: colors.warning,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  hoursNote,
                                  style: text.labelMedium?.copyWith(
                                    color: colors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's map in the list: still (so the page scrolls over it), with a
/// button to open it full screen.
class _DayMap extends StatelessWidget {
  const _DayMap({
    required this.stops,
    required this.route,
    required this.nextStop,
    required this.controller,
    required this.initialCenter,
    required this.onExpand,
  });

  final List<TripStop> stops;
  final List<LatLng>? route;
  final int? nextStop;
  final MapController controller;
  final LatLng initialCenter;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            _DayMapView(
              stops: stops,
              route: route,
              nextStop: nextStop,
              interactive: false,
              controller: controller,
              initialCenter: initialCenter,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: AppColors.of(context).surface,
                shape: const CircleBorder(),
                elevation: 1,
                child: AppIconButton(
                  icon: Icons.fullscreen_rounded,
                  tooltip: 'Full-screen map',
                  onPressed: onExpand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayMapView extends StatelessWidget {
  const _DayMapView({
    required this.stops,
    required this.route,
    required this.nextStop,
    required this.interactive,
    required this.initialCenter,
    this.controller,
  });

  final List<TripStop> stops;

  /// The road route; null draws dotted straight lines (order only).
  final List<LatLng>? route;
  final int? nextStop;
  final bool interactive;
  final LatLng initialCenter;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final path = route;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 12.8,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        osmTileLayer(),
        if (stops.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: path ?? [for (final s in stops) s.coordinates],
                color: AppTheme.forest,
                strokeWidth: 4.0,
                pattern: path != null
                    ? const StrokePattern.solid()
                    : StrokePattern.dotted(),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < stops.length; i++)
              Marker(
                point: stops[i].coordinates,
                width: 32,
                height: 32,
                child: StopNumberBadge(
                  number: i + 1,
                  done: stops[i].isCompleted,
                  highlight: i == nextStop,
                ),
              ),
          ],
        ),
        const OsmAttribution(),
      ],
    );
  }
}
