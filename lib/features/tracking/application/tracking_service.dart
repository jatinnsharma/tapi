import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/services/battery_settings_service.dart';
import '../../../core/services/firebase_status.dart';
import '../../../core/services/gps_fix.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/step_service.dart';
import '../../auth/application/auth_service.dart';
import '../../memories/domain/memory_model.dart';
import '../../social/application/footprint_service.dart';
import '../../social/data/social_repository.dart';
import '../../social/domain/activity_entry.dart';
import '../../social/domain/live_location.dart';
import '../data/adventure_repository.dart';
import '../domain/adventure_session.dart';
import '../domain/checkpoint.dart';
import '../domain/directions.dart';
import '../domain/route_point.dart';
import '../domain/trip_guard.dart';
import '../domain/trip_recorder.dart';
import '../domain/trip_split.dart';
import '../domain/trip_steps.dart';
import 'server_xp_service.dart';

class TrackingState {
  const TrackingState({
    this.session,
    this.routePoints = const [],
    this.checkpoints = const [],
    this.elapsed = Duration.zero,
    this.isOffRoute = false,
    this.isSharingLocation = false,
    this.destination,
    this.pendingArrival,
    this.xpNotice,
    this.phase = TripPhase.toTrekStart,
    this.metersToTrekStart,
    this.stepsCounting = false,
  });

  /// True once the phone's step sensor is reporting during this trip.
  final bool stepsCounting;

  final AdventureSession? session;

  /// Journey or trek, right now (see [TripSplit]).
  final TripPhase phase;

  /// How far the trek's start is, while still on the journey there. Null
  /// once the trek has started, or when the trip has no fixed start point.
  final double? metersToTrekStart;

  /// The place this adventure is heading to, when it was started from a
  /// place (rather than free exploration). Drives the live
  /// step-by-step directions.
  final Destination? destination;

  /// A place the user has reached on the ground. Its XP is paid once they
  /// confirm with a camera photo taken there.
  final Checkpoint? pendingArrival;

  /// The latest thing to tell the user about XP: why something didn't count,
  /// or a limit they've hit.
  final String? xpNotice;
  final List<RoutePoint> routePoints;
  final List<Checkpoint> checkpoints;
  final Duration elapsed;

  /// True when there are planned-but-unreached checkpoints and the user's
  /// current position is far from all of them — a simple heuristic for the
  /// spec's "off-route alert" safety feature.
  final bool isOffRoute;

  /// Opt-in: whether this adventure's live position is being shared with
  /// friends. Always starts false — "public users should never automatically
  /// receive someone's exact live location" per the spec.
  final bool isSharingLocation;

  bool get isActive => session?.status == AdventureStatus.active;
  bool get isPaused => session?.status == AdventureStatus.paused;
  bool get hasSession => session != null;

  double get distanceMeters => session?.distanceMeters ?? 0;

  TrackingState copyWith({
    AdventureSession? session,
    List<RoutePoint>? routePoints,
    List<Checkpoint>? checkpoints,
    Duration? elapsed,
    bool? isOffRoute,
    bool? isSharingLocation,
    Checkpoint? pendingArrival,
    bool clearPendingArrival = false,
    String? xpNotice,
    bool clearXpNotice = false,
    bool clearSession = false,
    TripPhase? phase,
    double? metersToTrekStart,
    bool clearMetersToTrekStart = false,
    bool? stepsCounting,
  }) {
    return TrackingState(
      session: clearSession ? null : (session ?? this.session),
      routePoints: routePoints ?? this.routePoints,
      checkpoints: checkpoints ?? this.checkpoints,
      elapsed: elapsed ?? this.elapsed,
      isOffRoute: isOffRoute ?? this.isOffRoute,
      isSharingLocation: isSharingLocation ?? this.isSharingLocation,
      destination: destination,
      pendingArrival: clearPendingArrival
          ? null
          : (pendingArrival ?? this.pendingArrival),
      xpNotice: clearXpNotice ? null : (xpNotice ?? this.xpNotice),
      phase: phase ?? this.phase,
      metersToTrekStart: clearMetersToTrekStart
          ? null
          : (metersToTrekStart ?? this.metersToTrekStart),
      stepsCounting: stepsCounting ?? this.stepsCounting,
    );
  }
}

/// What confirming an arrival with a photo did.
class ArrivalOutcome {
  const ArrivalOutcome({
    required this.paid,
    required this.message,
    this.xp = 0,
  });

  /// True when the place counted as reached.
  final bool paid;
  final int xp;
  final String message;
}

final trackingServiceProvider =
    NotifierProvider<TrackingService, TrackingState>(TrackingService.new);

class TrackingService extends Notifier<TrackingState> {
  static const _uuid = Uuid();
  static const Distance _distanceCalculator = Distance();

  /// Beyond this distance from every remaining checkpoint, the user is
  /// considered off-route.
  static const double _offRouteThresholdMeters = 1000;

  /// Most XP a user can earn from trips in one day (places and completion
  /// bonuses; achievement claims are separate). Stops farming.
  static const dailyTripXpCap = 1500;

  /// A place pays its XP once in this long.
  static const placeCooldown = Duration(days: 7);

  /// The trip's integrity checks: see [TripGuard].
  TripGuard _guard = TripGuard();

  /// What the server needs to re-judge this trip (see [TripRecorder]).
  TripRecorder? _recorder;

  /// Journey vs trek (see [TripSplit]).
  TripSplit _split = TripSplit();

  /// Steps from the phone's step sensor (see [TripSteps]).
  TripSteps _steps = TripSteps();
  StreamSubscription<StepReading>? _stepSubscription;

  StreamSubscription<GpsFix>? _locationSubscription;
  Timer? _ticker;
  DateTime? _lastTick;

  @override
  TrackingState build() {
    ref.onDispose(() {
      _locationSubscription?.cancel();
      _stepSubscription?.cancel();
      _ticker?.cancel();
    });
    return const TrackingState();
  }

  Future<void> startAdventure({
    required String title,
    List<Checkpoint> checkpoints = const [],
    String? groupAdventureId,
    Destination? destination,
  }) async {
    final repository = ref.read(adventureRepositoryProvider);
    final id = _uuid.v4();
    final session = AdventureSession(
      id: id,
      title: title,
      startedAt: DateTime.now(),
      status: AdventureStatus.active,
      groupAdventureId: groupAdventureId,
    );

    final seededCheckpoints = [
      for (var i = 0; i < checkpoints.length; i++)
        Checkpoint(
          // Unique per trip: the place's own id would clash with the
          // checkpoint of an earlier trip to the same place. The prefix stays,
          // because the destination checkpoint is recognised by it.
          id: '${checkpoints[i].id}@$id',
          adventureId: id,
          name: checkpoints[i].name,
          latitude: checkpoints[i].latitude,
          longitude: checkpoints[i].longitude,
          radiusMeters: checkpoints[i].radiusMeters,
          xpReward: checkpoints[i].xpReward,
          orderIndex: i,
        ),
    ];

    _guard = TripGuard();
    // The trek starts within 200 m of the place; with no place, at once.
    _split = TripSplit(trekStart: destination?.point);
    _steps = TripSteps();
    _recorder = TripRecorder(tripId: id, startedAt: session.startedAt);
    if (destination != null) {
      _recorder!.setPlace(
        id: destination.id,
        name: destination.name,
        latitude: destination.latitude,
        longitude: destination.longitude,
      );
    }
    // Tidy up empty leftovers of starts that failed part-way (best-effort).
    try {
      await repository.removeEmptyAbandonedTrips();
    } catch (_) {}
    await repository.createAdventureWithCheckpoints(session, seededCheckpoints);

    state = TrackingState(
      session: session,
      routePoints: const [],
      checkpoints: seededCheckpoints,
      elapsed: Duration.zero,
      destination: destination,
      phase: _split.phase,
    );

    _startTicker();
    _startLocationStream();
    unawaited(_startStepCounting());
  }

  /// Counts steps with the phone's step sensor, if it has one and the user
  /// allows it. Best-effort: without it the trip works the same.
  Future<void> _startStepCounting() async {
    await _stepSubscription?.cancel();
    _stepSubscription = null;
    try {
      final service = ref.read(stepServiceProvider);
      if (!service.supported || !await service.requestPermission()) return;
      if (!state.isActive) return;
      _stepSubscription = service.readings().listen(
        _onStepReading,
        onError: (Object _) {
          // No step sensor on this phone: carry on without steps.
          _stepSubscription?.cancel();
          _stepSubscription = null;
        },
        cancelOnError: true,
      );
    } catch (_) {
      // Permission or sensor unavailable: carry on without steps.
    }
  }

  void _onStepReading(StepReading reading) {
    final session = state.session;
    if (session == null || session.status != AdventureStatus.active) return;
    _steps.add(
      reading.total,
      reading.at,
      onTrek: _split.phase == TripPhase.trekking && !_split.inVehicle,
    );
    // Shown at once; saved with the next GPS update or at the finish.
    state = state.copyWith(
      session: session.copyWith(
        steps: _steps.steps,
        trekSteps: _steps.trekSteps,
      ),
      stepsCounting: true,
    );
  }

  void _startTicker() {
    _lastTick = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final last = _lastTick ?? now;
      _lastTick = now;
      state = state.copyWith(elapsed: state.elapsed + now.difference(last));
    });
  }

  void _startLocationStream() {
    final locationService = ref.read(locationServiceProvider);
    final batterySaving = ref.read(batterySavingModeProvider).value ?? false;
    _locationSubscription?.cancel();
    _locationSubscription = locationService
        .getAdventureTrackingStream(batterySaving: batterySaving)
        .listen(_onLocationUpdate);
  }

  Future<void> enableLiveSharing() async {
    if (!state.hasSession) return;
    state = state.copyWith(isSharingLocation: true);
  }

  Future<void> disableLiveSharing() async {
    state = state.copyWith(isSharingLocation: false);
    await _stopSharingBestEffort();
  }

  Future<void> _stopSharingBestEffort() async {
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null || !ref.read(firebaseReadyProvider)) return;
      await ref
          .read(socialRepositoryProvider)
          .stopLiveLocationSharing(user.uid);
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _shareLocationBestEffort(
    LatLng point,
    AdventureSession session,
  ) async {
    if (!state.isSharingLocation) return;
    try {
      if (!ref.read(firebaseReadyProvider)) return;
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      await ref
          .read(socialRepositoryProvider)
          .updateLiveLocation(
            LiveLocation(
              uid: user.uid,
              displayName: user.email?.split('@').first ?? 'Explorer',
              latitude: point.latitude,
              longitude: point.longitude,
              adventureTitle: session.title,
              updatedAt: DateTime.now(),
              sharing: true,
              groupAdventureId: session.groupAdventureId,
            ),
          );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _onLocationUpdate(GpsFix fix) async {
    final session = state.session;
    if (session == null || session.status != AdventureStatus.active) return;

    // Every reading is checked first: fake, imprecise or impossible ones are
    // dropped and never stored or counted.
    _recorder?.addFix(fix);
    final verdict = _guard.process(fix);
    final flag = verdict.flag;
    if (flag != null && state.xpNotice != flag.message) {
      state = state.copyWith(xpNotice: flag.message);
    }
    if (!verdict.accepted) return;
    _split.add(fix);
    final point = fix.position;

    final repository = ref.read(adventureRepositoryProvider);
    final now = DateTime.now();
    unawaited(_shareLocationBestEffort(point, session));

    final addedDistance = verdict.addedMeters;

    final routePoint = RoutePoint(
      adventureId: session.id,
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: now,
    );
    await repository.addRoutePoint(routePoint);

    final updatedSession = _withSplit(
      session.copyWith(distanceMeters: session.distanceMeters + addedDistance),
    );
    await repository.updateAdventure(updatedSession);

    final updatedCheckpoints = await _checkCheckpoints(
      point,
      repository,
      updatedSession,
    );

    state = state.copyWith(
      session: updatedSession,
      routePoints: [...state.routePoints, routePoint],
      checkpoints: updatedCheckpoints,
      isOffRoute: _computeIsOffRoute(point, updatedCheckpoints),
      phase: _split.phase,
      metersToTrekStart: _split.trekStarted
          ? null
          : _split.metersToTrekStart(point),
      clearMetersToTrekStart: _split.trekStarted,
    );
  }

  /// [session] with the trip's journey and trek so far.
  AdventureSession _withSplit(AdventureSession session) => session.copyWith(
    trekMeters: _split.trekMeters,
    trekSeconds: _split.trekTime.inSeconds,
    journeyMeters: _split.journeyMeters,
    journeySeconds: _split.journeyTime.inSeconds,
    steps: _steps.steps,
    trekSteps: _steps.trekSteps,
  );

  bool _computeIsOffRoute(LatLng point, List<Checkpoint> checkpoints) {
    // A single far-away destination isn't a "planned route": walking toward a
    // place 3 km away would otherwise read as off-route the whole way. The
    // directions panel guides those trips instead.
    final unreached = checkpoints.where(
      (c) => !c.isReached && !c.id.startsWith(Destination.checkpointIdPrefix),
    );
    if (unreached.isEmpty) return false;

    final nearestDistance = unreached
        .map((c) => _distanceCalculator(point, LatLng(c.latitude, c.longitude)))
        .reduce((a, b) => a < b ? a : b);
    return nearestDistance > _offRouteThresholdMeters;
  }

  /// Finds places the user is standing at. Reaching one doesn't pay XP by
  /// itself: it must pass the trip checks, then the user confirms with a
  /// camera photo (see [confirmArrivalWithPhoto]).
  Future<List<Checkpoint>> _checkCheckpoints(
    LatLng point,
    AdventureRepository repository,
    AdventureSession session,
  ) async {
    for (final checkpoint in state.checkpoints) {
      if (checkpoint.isReached) continue;
      final distance = _distanceCalculator(
        LatLng(checkpoint.latitude, checkpoint.longitude),
        point,
      );
      if (distance > checkpoint.radiusMeters) continue;

      final denial = _guard.arrivalDenial(
        target: LatLng(checkpoint.latitude, checkpoint.longitude),
        elapsed: state.elapsed,
      );
      if (denial != null) {
        if (state.xpNotice != denial.message) {
          state = state.copyWith(xpNotice: denial.message);
        }
        continue;
      }
      if (state.pendingArrival?.id != checkpoint.id) {
        state = state.copyWith(pendingArrival: checkpoint, clearXpNotice: true);
      }
    }
    return state.checkpoints;
  }

  /// Pays a place's XP once the user shows a photo taken there with the
  /// in-app camera. The photo only counts if the trip's last good GPS
  /// reading is recent and at the place, so it can't be taken elsewhere and
  /// submitted later.
  Future<ArrivalOutcome> confirmArrivalWithPhoto(Memory photo) async {
    final session = state.session;
    final pending = state.pendingArrival;
    if (session == null || pending == null) {
      return const ArrivalOutcome(
        paid: false,
        message: "There is no arrival to confirm.",
      );
    }

    final now = DateTime.now();
    final fresh = now.difference(photo.timestamp).inSeconds.abs() <= 120;
    final here = _guard.photoProvesPresence(
      target: LatLng(pending.latitude, pending.longitude),
      radiusMeters: pending.radiusMeters,
      now: now,
    );
    if (!fresh || !here) {
      return ArrivalOutcome(
        paid: false,
        message: 'Take the photo while you are at ${pending.name}.',
      );
    }

    _recorder?.markProofPhoto(photo.timestamp);
    final repository = ref.read(adventureRepositoryProvider);
    final reason = 'Checkpoint reached: ${pending.name}';
    final startOfDay = DateTime(now.year, now.month, now.day);

    var xp = pending.xpReward;
    String? note;
    if (await repository.hasXpReasonSince(
      reason,
      now.subtract(placeCooldown),
    )) {
      xp = 0;
      note =
          'You already earned XP at ${pending.name} in the last '
          '${placeCooldown.inDays} days. The visit still counts, '
          'but it earns no XP.';
    } else {
      final used = await repository.tripXpSince(startOfDay);
      final left = (dailyTripXpCap - used).clamp(0, dailyTripXpCap);
      if (left < xp) {
        xp = left;
        note = left == 0
            ? "You reached today's XP limit ($dailyTripXpCap). Come back "
                  'tomorrow for more.'
            : "You are nearly at today's XP limit, so this paid $left XP.";
      }
    }

    final reached = pending.copyWith(reachedAt: now);
    await repository.markCheckpointReached(reached);
    ref.invalidate(visitedPlaceIdsProvider);
    if (xp > 0) {
      await repository.recordXp(
        amount: xp,
        reason: reason,
        adventureId: session.id,
      );
    }
    final updated = session.copyWith(xpEarned: session.xpEarned + xp);
    await repository.updateAdventure(updated);

    state = state.copyWith(
      session: updated,
      checkpoints: [
        for (final c in state.checkpoints) c.id == reached.id ? reached : c,
      ],
      clearPendingArrival: true,
      xpNotice: note,
      clearXpNotice: note == null,
    );
    unawaited(_syncXpBestEffort());
    return ArrivalOutcome(
      paid: true,
      xp: xp,
      message: note ?? 'You made it to ${pending.name}!',
    );
  }

  Future<void> pauseAdventure() async {
    final session = state.session;
    if (session == null || session.status != AdventureStatus.active) return;

    _locationSubscription?.cancel();
    _ticker?.cancel();
    await _stepSubscription?.cancel();
    _stepSubscription = null;

    final repository = ref.read(adventureRepositoryProvider);
    final updated = _withSplit(session)
        .copyWith(status: AdventureStatus.paused);
    await repository.updateAdventure(updated);
    state = state.copyWith(session: updated);
  }

  Future<void> resumeAdventure() async {
    final session = state.session;
    if (session == null || session.status != AdventureStatus.paused) return;

    final repository = ref.read(adventureRepositoryProvider);
    final updated = session.copyWith(status: AdventureStatus.active);
    await repository.updateAdventure(updated);
    state = state.copyWith(session: updated);

    // The paused time is neither journey nor trek, and its steps don't count.
    _split.skipNextGap();
    _steps.skipNextGap();
    _startTicker();
    _startLocationStream();
    unawaited(_startStepCounting());
  }

  Future<AdventureSession?> finishAdventure() async {
    final session = state.session;
    if (session == null) return null;

    _locationSubscription?.cancel();
    _ticker?.cancel();
    await _stepSubscription?.cancel();
    _stepSubscription = null;

    final repository = ref.read(adventureRepositoryProvider);
    final now = DateTime.now();

    // Only a trip that passes the checks counts as completed and pays the
    // bonus. Anything else is kept in the journal as "not counted".
    // Judged on the trek only: the journey there doesn't make a trip.
    final denial = _guard.completionDenial(
      trekMeters: _split.trekMeters,
      trekTime: _split.trekTime,
    );
    var bonus = 0;
    String? note = denial?.message;
    if (denial == null) {
      final used = await repository.tripXpSince(
        DateTime(now.year, now.month, now.day),
      );
      bonus = (dailyTripXpCap - used).clamp(0, 100);
      if (bonus < 100) {
        note =
            "You reached today's XP limit ($dailyTripXpCap), so the "
            'completion bonus was $bonus XP.';
      }
    }
    if (state.pendingArrival case final missed?) {
      note =
          'You reached ${missed.name} but did not take the confirmation '
          'photo, so its XP was not paid.';
    }

    final updated = _withSplit(session).copyWith(
      status: denial == null
          ? AdventureStatus.completed
          : AdventureStatus.unverified,
      endedAt: now,
      durationSeconds: state.elapsed.inSeconds,
      xpEarned: session.xpEarned + bonus,
    );
    await repository.updateAdventure(updated);
    // A trip that failed the checks no longer marks its places visited.
    ref.invalidate(visitedPlaceIdsProvider);
    if (bonus > 0) {
      await repository.recordXp(
        amount: bonus,
        reason: 'Adventure completed: ${session.title}',
        adventureId: session.id,
      );
    }

    state = state.copyWith(
      session: updated,
      isSharingLocation: false,
      clearPendingArrival: true,
      xpNotice: note,
      clearXpNotice: note == null,
    );
    unawaited(_postActivityBestEffort(updated, state.routePoints));
    unawaited(_stopSharingBestEffort());
    unawaited(_syncXpBestEffort());
    unawaited(_syncFootprintBestEffort());
    unawaited(_submitTripBestEffort(now));
    return updated;
  }

  /// Sends the finished trip to the server to be judged again (see
  /// [FeatureFlags.serverVerifiedXp]). Best-effort: a failure must never
  /// affect finishing a trip, and the server answers a repeat harmlessly.
  Future<void> _submitTripBestEffort(DateTime endedAt) async {
    final recorder = _recorder;
    _recorder = null;
    if (!FeatureFlags.serverVerifiedXp || recorder == null) return;
    try {
      if (!ref.read(firebaseReadyProvider)) return;
      if (ref.read(authStateProvider).value == null) return;
      await ref
          .read(serverXpServiceProvider)
          .submitTrip(recorder.payload(endedAt));
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Refreshes the user's shareable footprint (route history + visited
  /// places) if they've chosen to share it. Best-effort, like the other
  /// social syncs: a failure must never affect finishing an adventure.
  Future<void> _syncFootprintBestEffort() async {
    try {
      if (!ref.read(firebaseReadyProvider)) return;
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      await ref
          .read(footprintServiceProvider)
          .refreshIfShared(
            uid: user.uid,
            fallbackName: user.email?.split('@').first ?? 'Explorer',
          );
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Mirrors the device-local XP total onto the user's Firestore profile, so
  /// things that need to see XP without the device being online — a Group's
  /// total XP, say — have somewhere to read it from. XP itself still lives
  /// only in local SQLite; this is a denormalized, best-effort copy.
  Future<void> _syncXpBestEffort() async {
    try {
      if (!ref.read(firebaseReadyProvider)) return;
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final socialRepository = ref.read(socialRepositoryProvider);
      final totalXp = await ref.read(adventureRepositoryProvider).getTotalXp();
      final profile = await socialRepository.getProfile(user.uid);
      if (profile == null || profile.totalXp == totalXp) return;
      await socialRepository.setTotalXp(user.uid, totalXp);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Shares a completed adventure to the social feed, if Firebase is
  /// configured and the user is signed in. Never throws — a social-posting
  /// failure must not affect the adventure that was just completed.
  Future<void> _postActivityBestEffort(
    AdventureSession session,
    List<RoutePoint> routePoints,
  ) async {
    try {
      if (!ref.read(firebaseReadyProvider)) return;
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      // The route itself is deliberately not attached to the post: feed posts
      // are visible to every friend, whereas routes are shared only through
      // the user's footprint, which honours their map-visibility choice.
      await ref
          .read(socialRepositoryProvider)
          .postActivity(
            ActivityEntry(
              uid: user.uid,
              displayName: user.email?.split('@').first ?? 'Explorer',
              title: session.title,
              // Activity stats count the trek only.
              distanceKm: session.trekMeters / 1000,
              xpEarned: session.xpEarned,
              timestamp: DateTime.now(),
            ),
          );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> discardAdventure() async {
    final session = state.session;
    final wasSharing = state.isSharingLocation;
    _locationSubscription?.cancel();
    _ticker?.cancel();
    await _stepSubscription?.cancel();
    _stepSubscription = null;

    if (session != null) {
      final repository = ref.read(adventureRepositoryProvider);
      await repository.deleteAdventure(session.id);
      ref.invalidate(visitedPlaceIdsProvider);
    }

    state = const TrackingState();
    if (wasSharing) unawaited(_stopSharingBestEffort());
  }

  void reset() {
    _locationSubscription?.cancel();
    _ticker?.cancel();
    state = const TrackingState();
  }
}
