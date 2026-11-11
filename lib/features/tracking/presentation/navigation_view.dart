part of 'tracking_screen.dart';

// Google Maps-style live navigation for a trip to a place: the map fills the
// screen, the next turn is a big banner on top, and time, distance and the
// trip controls sit in a bottom sheet that pulls up for details.

/// Route colour: the familiar navigation blue, readable on any map tile.
const _navBlue = Color(0xFF1A73E8);
const _navBlueDark = Color(0xFF0B57D0);

enum _CameraMode {
  /// Centred on the user, ahead of them, turning with their heading.
  follow,

  /// The whole remaining route.
  overview,

  /// The user moved the map themselves.
  free,
}

class _NavigationView extends ConsumerStatefulWidget {
  const _NavigationView({
    required this.destination,
    required this.onTakePhoto,
    required this.onFinish,
    required this.onAddMemory,
  });

  final Destination destination;
  final void Function(Checkpoint place) onTakePhoto;
  final Future<void> Function() onFinish;
  final Future<void> Function() onAddMemory;

  @override
  ConsumerState<_NavigationView> createState() => _NavigationViewState();
}

class _NavigationViewState extends ConsumerState<_NavigationView> {
  static const _distance = Distance();

  // --- Guidance ---------------------------------------------------------------

  /// The last route that loaded. Kept so guidance continues if recalculating
  /// fails, e.g. when the connection drops mid-trip.
  RouteDirections? _route;

  /// Index of the last manoeuvre passed (0 = the start).
  int _passed = 0;

  /// Where the user is along the route line, updated on every fix.
  RouteProgress? _progress;

  /// Direction of travel in degrees from north, from recent GPS fixes.
  double? _heading;

  int _offRouteFixes = 0;
  DateTime? _lastAutoReroute;
  bool _rerouting = false;

  static const _offRouteFixesNeeded = 3;
  static const _rerouteCooldown = Duration(seconds: 30);

  // Distances that depend on speed: a driver needs warnings further ahead.
  double get _passRadius => (_route?.driving ?? false) ? 45 : 30;
  double get _nearTurn => (_route?.driving ?? false) ? 120 : 40;
  double get _offRouteMeters => (_route?.driving ?? false) ? 100 : 60;
  double get _thenWithin => (_route?.driving ?? false) ? 300 : 100;

  // --- Voice ------------------------------------------------------------------

  final FlutterTts _tts = FlutterTts();
  bool _voiceOn = true;
  int _spokenStep = -1;
  int _spokenNearStep = -1;
  bool _spokenArrival = false;

  // --- Camera and layout ------------------------------------------------------

  final MapController _map = MapController();
  bool _mapReady = false;
  _CameraMode _camera = _CameraMode.follow;
  bool _headingUp = true;
  Size _screen = Size.zero;

  final DraggableScrollableController _sheet = DraggableScrollableController();
  double _sheetHeight = _sheetMinHeight;

  /// Collapsed sheet: handle, time and distance, Pause/Finish.
  static const _sheetMinHeight = 172.0;

  /// Rough height of the turn banner and alerts, for keeping the route clear
  /// of them.
  double get _topInset => MediaQuery.paddingOf(context).top + 150;

  @override
  void initState() {
    super.initState();
    // Instructions are written in English. Best effort: the device may not
    // have this voice installed, in which case its default voice is used.
    _tts.setLanguage('en-US').catchError((Object _) => null);
    _tts.setSpeechRate(0.5).catchError((Object _) => null);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  LatLng? get _me {
    final points = ref.read(trackingServiceProvider).routePoints;
    return points.isEmpty
        ? null
        : LatLng(points.last.latitude, points.last.longitude);
  }

  void _recalculate() {
    setState(() => _rerouting = true);
    ref.invalidate(routeToDestinationProvider(widget.destination));
  }

  /// A new route arrived (first load, reroute or mode change).
  void _onRoute(RouteDirections route) {
    _route = route;
    _passed = 0;
    _rerouting = false;
    _spokenStep = -1;
    _spokenNearStep = -1;
    final me = _me;
    _progress = me == null ? null : route.progressAt(me);
    _updateHeading();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _announce();
      _updateCamera();
    });
  }

  /// Every GPS fix: heading, progress, step advance, voice, auto-reroute and
  /// camera.
  void _onFix() {
    final points = ref.read(trackingServiceProvider).routePoints;
    if (points.isEmpty) return;
    final me = LatLng(points.last.latitude, points.last.longitude);

    final route = _route;
    if (route != null) {
      _progress = route.progressAt(
        me,
        fromSegment: _progress?.segmentIndex ?? 0,
      );
    }
    _updateHeading();

    if (route != null) {
      var passed = _passed;
      // Only a few steps ahead, so a route that loops back near an earlier
      // point can't jump the guidance forward.
      for (var i = passed + 1; i < route.steps.length && i <= passed + 3; i++) {
        if (_distance(me, route.steps[i].location) <= _passRadius) passed = i;
      }
      _passed = passed;
      _announce();

      final offBy = route.distanceFromPath(me);
      if (offBy != null) {
        _offRouteFixes = offBy > _offRouteMeters ? _offRouteFixes + 1 : 0;
        final last = _lastAutoReroute;
        final cooled =
            last == null || DateTime.now().difference(last) > _rerouteCooldown;
        if (_offRouteFixes >= _offRouteFixesNeeded && cooled && !_rerouting) {
          _offRouteFixes = 0;
          _lastAutoReroute = DateTime.now();
          _recalculate();
        }
      }
    }
    setState(() {});
    _updateCamera();
  }

  /// Direction of travel from the latest fixes far enough apart to mean
  /// movement; standing still, the direction of the route ahead.
  void _updateHeading() {
    final points = ref.read(trackingServiceProvider).routePoints;
    if (points.isEmpty) return;
    final me = LatLng(points.last.latitude, points.last.longitude);
    for (var i = points.length - 2; i >= 0 && i >= points.length - 6; i--) {
      final prev = LatLng(points[i].latitude, points[i].longitude);
      if (_distance(prev, me) >= 4) {
        _heading = bearingBetween(prev, me);
        return;
      }
    }
    final ahead = _progress?.remainingPath;
    if (_heading == null && ahead != null && ahead.length > 1) {
      _heading = bearingBetween(ahead[0], ahead[1]);
    }
  }

  int get _nextIndex {
    final steps = _route?.steps ?? const [];
    return steps.isEmpty ? 0 : (_passed + 1).clamp(0, steps.length - 1);
  }

  /// Metres to [target] along the remaining route (as Google shows "in
  /// 200 m"), or in a straight line without a route.
  double? _alongRouteTo(LatLng target) {
    final me = _me;
    final progress = _progress;
    if (progress == null) {
      return me == null ? null : _distance(me, target);
    }
    final path = progress.remainingPath;
    var along = 0.0;
    var bestAlong = 0.0;
    var bestGap = double.infinity;
    for (var i = 0; i < path.length; i++) {
      if (i > 0) along += _distance(path[i - 1], path[i]);
      final gap = _distance(path[i], target);
      if (gap < bestGap) {
        bestGap = gap;
        bestAlong = along;
      }
      // The manoeuvre point is on the line; once we're well past it, stop.
      if (bestGap < 15 && gap > bestGap + 200) break;
    }
    return bestAlong + (bestGap < 25 ? 0 : bestGap);
  }

  // --- Voice ------------------------------------------------------------------

  Future<void> _say(String text) async {
    if (!_voiceOn || !mounted) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // No text-to-speech engine: guidance stays visual only.
    }
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    if (!_voiceOn) _tts.stop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_voiceOn ? 'Voice guidance on' : 'Voice guidance muted'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Speaks the next instruction once when it comes up ("In 120 metres, turn
  /// left onto ..."), then again at the turn ("Now, turn left onto ...").
  void _announce() {
    final route = _route;
    if (route == null || route.steps.isEmpty) return;
    final next = _nextIndex;
    final step = route.steps[next];
    final toNext = _alongRouteTo(step.location);
    final isLast = next == route.steps.length - 1;

    if (next != _spokenStep) {
      _spokenStep = next;
      if (toNext != null && toNext > _nearTurn) {
        _say(
          'In ${_spokenDistance(toNext)}, ${_lowerFirst(step.instruction)}.',
        );
      } else {
        _spokenNearStep = next;
        _say('${step.instruction}.');
      }
    } else if (!isLast &&
        toNext != null &&
        toNext <= _nearTurn &&
        _spokenNearStep != next) {
      _spokenNearStep = next;
      _say('Now, ${_lowerFirst(step.instruction)}.');
    }
  }

  String _spokenDistance(double meters) {
    if (meters < 1000) return '${(meters / 10).round() * 10} metres';
    return '${(meters / 1000).toStringAsFixed(1)} kilometres';
  }

  String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  // --- Camera -----------------------------------------------------------------

  double get _followZoom => (_route?.driving ?? false) ? 16.5 : 17.5;

  void _updateCamera() {
    if (!_mapReady || !mounted) return;
    switch (_camera) {
      case _CameraMode.follow:
        final me = _me;
        if (me == null) {
          _fitRoute();
          return;
        }
        _map.rotate(_headingUp && _heading != null ? -_heading! : 0);
        // Put the user in the lower part of the space between the banner
        // and the sheet, so more of the road ahead is visible.
        final top = _topInset;
        final bottom = _screen.height - _sheetHeight;
        final target = top + (bottom - top) * 0.72;
        _map.move(
          me,
          _followZoom,
          offset: Offset(0, target - _screen.height / 2),
        );
      case _CameraMode.overview:
        _fitRoute();
      case _CameraMode.free:
        break;
    }
  }

  void _fitRoute() {
    if (!_mapReady) return;
    final me = _me;
    final points = [
      ...?(_progress?.remainingPath ?? _route?.path),
      widget.destination.point,
      ?me,
    ];
    _map.rotate(0);
    if (points.length < 2) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: EdgeInsets.fromLTRB(48, _topInset, 48, _sheetHeight + 32),
        maxZoom: 17,
      ),
    );
  }

  void _setCamera(_CameraMode mode) {
    setState(() => _camera = mode);
    _updateCamera();
  }

  // --- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final routeAsync = ref.watch(
      routeToDestinationProvider(widget.destination),
    );
    final tracking = ref.watch(trackingServiceProvider);
    final mode = ref.watch(travelModeProvider);

    final fresh = routeAsync.hasValue && !routeAsync.isLoading
        ? routeAsync.value
        : null;
    if (fresh != null && !identical(fresh, _route)) _onRoute(fresh);
    if (routeAsync.hasError && !routeAsync.isLoading) _rerouting = false;

    ref.listen(
      trackingServiceProvider.select((s) => s.routePoints.length),
      (_, _) => _onFix(),
    );

    final arrived = tracking.checkpoints.any(
      (c) => c.id.startsWith(Destination.checkpointIdPrefix) && c.isReached,
    );
    if (arrived && !_spokenArrival) {
      _spokenArrival = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _say('You have arrived at ${widget.destination.name}.'),
      );
    }

    final route = _route;
    final remaining =
        _progress?.remainingMeters ??
        (route == null || _me == null
            ? null
            : _distance(_me!, widget.destination.point));
    final seconds = route == null || remaining == null
        ? null
        : remaining / route.metersPerSecond;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          _screen = constraints.biggest;
          final minFraction = (_sheetMinHeight / _screen.height).clamp(
            0.1,
            0.5,
          );
          final topPad = MediaQuery.paddingOf(context).top;

          return Stack(
            children: [
              Positioned.fill(
                key: const ValueKey('trip-map'),
                child: _buildMap(tracking),
              ),

              // Turn banner and alerts.
              Positioned(
                left: 10,
                right: 10,
                top: topPad + 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBanner(tracking, routeAsync, arrived),
                    ..._buildAlerts(tracking, routeAsync),
                  ],
                ),
              ),

              // Map buttons, riding just above the sheet.
              Positioned(
                right: 12,
                bottom: _sheetHeight + 12,
                child: _buildMapButtons(),
              ),
              if (_camera == _CameraMode.free ||
                  _camera == _CameraMode.overview)
                Positioned(
                  left: 12,
                  bottom: _sheetHeight + 12,
                  child: FloatingActionButton.extended(
                    heroTag: 'nav-recenter',
                    onPressed: () => _setCamera(_CameraMode.follow),
                    backgroundColor: Colors.white,
                    foregroundColor: _navBlueDark,
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text(
                      'Re-centre',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),

              NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  final h = n.extent * _screen.height;
                  if ((h - _sheetHeight).abs() > 1) {
                    setState(() => _sheetHeight = h);
                  }
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: minFraction,
                  minChildSize: minFraction,
                  maxChildSize: 0.9,
                  snap: true,
                  snapSizes: const [0.55],
                  builder: (context, scroll) => _buildSheet(
                    scroll,
                    tracking,
                    route,
                    remaining,
                    seconds,
                    mode,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Map --------------------------------------------------------------------

  Widget _buildMap(TrackingState tracking) {
    final walked = [
      for (final p in tracking.routePoints) LatLng(p.latitude, p.longitude),
    ];
    final me = walked.isEmpty ? null : walked.last;
    final route = _route;
    final ahead = _progress?.remainingPath ?? route?.path ?? const <LatLng>[];

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: me ?? widget.destination.point,
        initialZoom: 16,
        onMapReady: () {
          _mapReady = true;
          _updateCamera();
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _camera != _CameraMode.free) {
            setState(() => _camera = _CameraMode.free);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.real_world_exploration',
          tileProvider: CachedTileProvider(),
        ),
        PolylineLayer(
          polylines: [
            // Your trail so far, in your rank's colour.
            if (walked.length >= 2)
              Polyline(
                points: walked,
                color:
                    ref.watch(rankStyleProvider).value?.equipped.trail ??
                    AppTheme.amber,
                strokeWidth: 4,
              ),
            // The way ahead; it shrinks behind you as you go.
            if (ahead.length >= 2)
              Polyline(
                points: ahead,
                color: _navBlue,
                strokeWidth: 7,
                borderColor: _navBlueDark,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.destination.point,
              width: 48,
              height: 48,
              alignment: Alignment.topCenter,
              rotate: true, // Stays upright when the map turns.
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFFEA4335),
                size: 48,
                shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
              ),
            ),
            if (me != null)
              Marker(
                key: const ValueKey('nav-me'),
                point: me,
                width: 46,
                height: 46,
                // Turns with the map, so the arrow points the real way.
                rotate: false,
                child: _NavArrow(heading: _heading),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMapButtons() {
    final rotated = _mapReady && _map.camera.rotation.abs() > 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapButton(
          icon: _voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          tooltip: _voiceOn ? 'Mute voice guidance' : 'Turn on voice guidance',
          onPressed: _toggleVoice,
        ),
        const SizedBox(height: 10),
        _MapButton(
          tooltip: _headingUp ? 'North up' : 'Heading up',
          onPressed: () {
            setState(() => _headingUp = !_headingUp);
            if (_camera != _CameraMode.follow) {
              _setCamera(_CameraMode.follow);
            } else {
              _updateCamera();
            }
          },
          child: Transform.rotate(
            angle: rotated ? _map.camera.rotation * math.pi / 180 : 0,
            child: Icon(
              _headingUp ? Icons.navigation_rounded : Icons.explore_rounded,
              color: _headingUp ? _navBlueDark : const Color(0xFFEA4335),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _MapButton(
          icon: Icons.alt_route_rounded,
          tooltip: 'Route overview',
          selected: _camera == _CameraMode.overview,
          onPressed: () => _setCamera(_CameraMode.overview),
        ),
        const SizedBox(height: 10),
        _MapButton(
          icon: Icons.add_a_photo_outlined,
          tooltip: 'Add a memory',
          onPressed: widget.onAddMemory,
        ),
      ],
    );
  }

  // --- Banner -----------------------------------------------------------------

  Widget _buildBanner(
    TrackingState tracking,
    AsyncValue<RouteDirections> routeAsync,
    bool arrived,
  ) {
    if (tracking.pendingArrival case final pending?) {
      return _Banner(
        color: AppTheme.amber,
        foreground: AppTheme.ink,
        icon: Icons.photo_camera_rounded,
        title: "You've arrived at ${pending.name}",
        subtitle: 'Take a photo here to confirm your visit and claim your XP.',
        action: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.ink,
            shape: const StadiumBorder(),
          ),
          onPressed: () => widget.onTakePhoto(pending),
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: const Text('Take photo'),
        ),
      );
    }
    if (arrived) {
      return _Banner(
        color: AppTheme.emerald,
        icon: Icons.celebration_rounded,
        title: 'You made it to ${widget.destination.name}!',
        subtitle: 'Visit confirmed. Tap Finish when you are done.',
      );
    }

    final route = _route;
    if (route == null) {
      if (routeAsync.isLoading) {
        return _Banner(
          icon: Icons.route_rounded,
          title: 'Finding the best route…',
          subtitle: 'To ${widget.destination.name}',
          progress: true,
        );
      }
      final me = _me;
      return _Banner(
        color: const Color(0xFF5F6368),
        icon: Icons.explore_outlined,
        title: 'Head toward ${widget.destination.name}',
        subtitle: me == null
            ? 'Directions are unavailable right now.'
            : 'No directions right now. ${_formatMeters(_distance(me, widget.destination.point))} away in a straight line.',
        action: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _recalculate,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
    }

    final steps = route.steps;
    if (steps.isEmpty) {
      return _Banner(
        icon: Icons.flag_rounded,
        title: 'Head to ${widget.destination.name}',
        subtitle: 'Follow the blue line.',
      );
    }
    final next = _nextIndex;
    final step = steps[next];
    final toNext = _alongRouteTo(step.location);
    final then = next + 1 < steps.length && step.distanceMeters <= _thenWithin
        ? steps[next + 1]
        : null;

    return GestureDetector(
      onTap: () => _showAllSteps(route, next),
      child: _Banner(
        key: const ValueKey('nav-banner'),
        icon: step.icon,
        distance: toNext == null ? null : _formatMeters(toNext),
        title: step.instruction,
        then: then,
      ),
    );
  }

  List<Widget> _buildAlerts(
    TrackingState tracking,
    AsyncValue<RouteDirections> routeAsync,
  ) {
    final notes = <Widget>[];
    void chip(IconData icon, String text, Color color) => notes.add(
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.white,
            elevation: 3,
            shape: StadiumBorder(side: BorderSide(color: color, width: 1.2)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (_rerouting) {
      chip(Icons.alt_route_rounded, 'Rerouting…', _navBlue);
    } else if (routeAsync.hasError && _route != null) {
      chip(
        Icons.cloud_off_rounded,
        'Offline: using your last route',
        Colors.grey,
      );
    }
    if (tracking.routePoints.isEmpty) {
      chip(Icons.gps_not_fixed_rounded, 'Waiting for GPS…', Colors.orange);
    }
    if (tracking.xpNotice case final notice?) {
      chip(Icons.info_outline_rounded, notice, Colors.orange);
    }
    final weather = ref.watch(currentWeatherProvider).value;
    if (weather != null && weather.isSevere) {
      chip(
        Icons.thunderstorm_rounded,
        '${weather.conditionDescription} (${weather.temperature.round()}°C). Take care.',
        Colors.red,
      );
    }
    return notes;
  }

  // --- Sheet ------------------------------------------------------------------

  Widget _buildSheet(
    ScrollController scroll,
    TrackingState tracking,
    RouteDirections? route,
    double? remaining,
    double? seconds,
    TravelMode? chosenMode,
  ) {
    final session = tracking.session!;
    final service = ref.read(trackingServiceProvider.notifier);
    final isActive = session.status == AdventureStatus.active;
    final effectiveMode = route == null
        ? chosenMode
        : (route.driving ? TravelMode.car : TravelMode.foot);

    final minutes = seconds == null
        ? null
        : (seconds / 60).ceil().clamp(1, 99999);
    final arrival = seconds == null
        ? null
        : DateFormat.jm().format(
            DateTime.now().add(Duration(seconds: seconds.round())),
          );

    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  tooltip: 'Back (the trip keeps running)',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      minutes == null ? '--' : _formatMinutes(minutes),
                      key: const ValueKey('nav-eta'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF188038),
                      ),
                    ),
                    Text(
                      [
                        if (remaining != null) _formatMeters(remaining),
                        if (arrival != null) 'Arrive $arrival',
                        if (remaining == null) widget.destination.name,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<TravelMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: _navBlue.withValues(alpha: 0.15),
                  selectedForegroundColor: _navBlueDark,
                ),
                segments: const [
                  ButtonSegment(
                    value: TravelMode.foot,
                    icon: Icon(Icons.directions_walk_rounded),
                    tooltip: 'Walking directions',
                  ),
                  ButtonSegment(
                    value: TravelMode.car,
                    icon: Icon(Icons.directions_car_rounded),
                    tooltip: 'Driving directions',
                  ),
                ],
                selected: {?effectiveMode},
                emptySelectionAllowed: true,
                onSelectionChanged: (picked) {
                  if (picked.isEmpty) return;
                  ref.read(travelModeProvider.notifier).choose(picked.first);
                  setState(() {
                    _rerouting = true;
                    _route = null;
                    _progress = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isActive
                      ? service.pauseAdventure
                      : service.resumeAdventure,
                  icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
                  label: Text(isActive ? 'Pause' : 'Resume'),
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onFinish,
                  icon: const Icon(Icons.flag),
                  label: const Text('Finish'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD93025),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),

          // Pulled up: directions, trip details and the rest.
          const SizedBox(height: 22),
          if (route != null && route.steps.isNotEmpty) ...[
            Text(
              'Directions · ${_formatMeters(route.distanceMeters)} ${route.driving ? 'by road' : 'on foot'}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < route.steps.length; i++)
              _StepRow(
                step: route.steps[i],
                number: i + 1,
                status: i < _nextIndex
                    ? _StepStatus.done
                    : (i == _nextIndex
                          ? _StepStatus.current
                          : _StepStatus.upcoming),
              ),
            const SizedBox(height: 10),
          ],
          LiveTripCard(
            session: session,
            elapsed: tracking.elapsed,
            phase: tracking.phase,
            metersToTrekStart: tracking.metersToTrekStart,
            placeName: widget.destination.name,
            stepsCounting: tracking.stepsCounting,
          ),
          const SizedBox(height: 14),
          _MemoriesRow(adventureId: session.id),
          const SizedBox(height: 14),
          const _LiveSharingToggle(),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: service.discardAdventure,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Discard trip'),
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllSteps(RouteDirections route, int next) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'Directions to ${widget.destination.name}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatMeters(route.distanceMeters)} · ~${_formatMinutes((route.durationSeconds / 60).ceil())}',
              style: const TextStyle(color: AppTheme.inkMuted),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < route.steps.length; i++)
              _StepRow(
                step: route.steps[i],
                number: i + 1,
                status: i < next
                    ? _StepStatus.done
                    : (i == next ? _StepStatus.current : _StepStatus.upcoming),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatMinutes(int minutes) =>
    minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${minutes % 60} min';

/// The top banner: the next turn as Google Maps shows it, or a status.
class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.distance,
    this.then,
    this.action,
    this.progress = false,
    this.color = const Color(0xFF0F7B45),
    this.foreground = Colors.white,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Distance to the turn, shown big ("120 m").
  final String? distance;

  /// The turn right after this one, when it comes soon.
  final DirectionStep? then;
  final Widget? action;
  final bool progress;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final muted = foreground.withValues(alpha: 0.85);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: color,
          elevation: 6,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(18),
            bottom: Radius.circular(then == null ? 18 : 0),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: foreground, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (distance != null)
                            Text(
                              distance!,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: distance == null ? foreground : muted,
                              fontSize: distance == null ? 19 : 16.5,
                              fontWeight: distance == null
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                color: muted,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (progress) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    minHeight: 3,
                    color: foreground,
                    backgroundColor: foreground.withValues(alpha: 0.25),
                  ),
                ],
                if (action != null)
                  Align(alignment: Alignment.centerRight, child: action),
              ],
            ),
          ),
        ),
        if (then != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Color.lerp(color, Colors.black, 0.25),
              elevation: 6,
              shadowColor: Colors.black45,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Then',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(then!.icon, color: foreground, size: 22),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// White round map button, as on Google Maps.
class _MapButton extends StatelessWidget {
  const _MapButton({
    this.icon,
    this.child,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? const Color(0xFFD2E3FC) : Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black45,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: child ?? Icon(icon, color: AppTheme.ink, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// "You" while navigating: a blue arrow pointing the way you're moving (a dot
/// before the heading is known).
class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.heading});

  final double? heading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You are here',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: _navBlue.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _navBlue,
            ),
            child: heading == null
                ? const SizedBox.expand()
                : Transform.rotate(
                    angle: heading! * math.pi / 180,
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
