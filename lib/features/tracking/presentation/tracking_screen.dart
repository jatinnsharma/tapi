import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';

import '../../weather/application/weather_service.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../../memories/data/memory_repository.dart';
import '../../memories/domain/memory_model.dart';
import '../../map/cached_tile_provider.dart';
import '../../memories/presentation/camera_screen.dart';
import '../../memories/presentation/memory_capture.dart';
import '../../profile/application/rank_style_service.dart';

import 'package:latlong2/latlong.dart';

import '../application/tracking_service.dart';
import '../data/directions_service.dart';
import '../domain/adventure_session.dart';
import '../domain/checkpoint.dart';
import '../domain/directions.dart';
import 'journey_trek_breakdown.dart';
import 'live_trip_card.dart';
import 'start_adventure_view.dart';
import 'trip_not_counted_checklist.dart';

import 'trip_share_sheet.dart';

part 'navigation_view.dart';

final _adventureMemoriesProvider = FutureProvider.autoDispose
    .family<List<Memory>, String>((ref, adventureId) {
      return ref.watch(memoryRepositoryProvider).getByAdventure(adventureId);
    });

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({
    super.key,
    this.title = 'New Adventure',
    this.destination,
    this.autoStart = false,
  });

  final String title;

  /// A place to guide the user to, with live step-by-step directions.
  final Destination? destination;

  /// Begin tracking immediately instead of showing the start view.
  final bool autoStart;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  /// Auto-start fires once. Without this, discarding the adventure would
  /// bring the screen back to "no session" and start another one.
  bool _autoStartUsed = false;

  @override
  Widget build(BuildContext context) {
    final trackingState = ref.watch(trackingServiceProvider);
    final trackingService = ref.read(trackingServiceProvider.notifier);
    final weatherAsync = ref.watch(currentWeatherProvider);

    // Reaching a place on the ground doesn't pay XP by itself: ask for a
    // photo taken there as proof, the moment the trip checks pass.
    ref.listen<String?>(
      trackingServiceProvider.select((s) => s.pendingArrival?.id),
      (before, now) {
        final pending = ref.read(trackingServiceProvider).pendingArrival;
        if (before == null && now != null && pending != null) {
          _promptArrivalPhoto(pending);
        }
      },
    );

    if (!trackingState.hasSession) {
      final destination = widget.destination;
      final title = widget.title;
      final checkpoints = destination != null
          ? [destination.toCheckpoint()]
          : const <Checkpoint>[];

      if (widget.autoStart && !_autoStartUsed) {
        return _AutoStartView(
          title: title,
          checkpoints: checkpoints,
          destination: destination,
          onStarted: () => _autoStartUsed = true,
        );
      }
      return StartAdventureView(
        title: title,
        checkpointTemplates: checkpoints,
        destination: destination,
      );
    }

    final session = trackingState.session!;
    final elapsed = trackingState.elapsed;

    // Heading to a place: full-screen, Google Maps-style navigation.
    if (trackingState.destination case final destination?) {
      return _NavigationView(
        destination: destination,
        onTakePhoto: _takeArrivalPhoto,
        onFinish: () async {
          final finished = await trackingService.finishAdventure();
          if (context.mounted && finished != null) {
            _showSummary(context, finished);
          }
        },
        onAddMemory: () async {
          final saved = await showAddMemorySheet(
            context,
            adventureId: session.id,
          );
          if (saved > 0) {
            ref.invalidate(_adventureMemoriesProvider(session.id));
          }
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: 'Add a memory',
            onPressed: () async {
              final saved = await showAddMemorySheet(
                context,
                adventureId: session.id,
              );
              if (saved > 0) {
                ref.invalidate(_adventureMemoriesProvider(session.id));
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: AppSpacing.page,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The page scrolls; Pause and Finish stay pinned below.
            final content = Column(
              children: [
                if (trackingState.xpNotice case final notice?)
                  _AlertBanner(
                    color: Colors.orange,
                    icon: Icons.info_outline_rounded,
                    child: Text(
                      notice,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (trackingState.pendingArrival case final pending?)
                  _ArrivalProofCard(
                    place: pending.name,
                    onTakePhoto: () => _takeArrivalPhoto(pending),
                  ),
                if (trackingState.isOffRoute)
                  const _AlertBanner(
                    color: Colors.orange,
                    icon: Icons.warning_amber,
                    child: Text(
                      "You're far from your planned route and checkpoints.",
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                weatherAsync.maybeWhen(
                  data: (weather) {
                    if (weather != null && weather.isSevere) {
                      return _AlertBanner(
                        color: Colors.red,
                        icon: Icons.thunderstorm,
                        child: Text(
                          'Weather Warning: ${weather.conditionDescription} (${weather.temperature}°C). Proceed with caution.',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
                LiveTripCard(
                  session: session,
                  elapsed: elapsed,
                  phase: trackingState.phase,
                  metersToTrekStart: trackingState.metersToTrekStart,
                  placeName: trackingState.destination?.name,
                  stepsCounting: trackingState.stepsCounting,
                ),
                const SizedBox(height: 16),
                _MemoriesRow(adventureId: session.id),
                const SizedBox(height: 16),
                const _LiveSharingToggle(),
                // Free exploration: the planned checkpoints.
                ...[
                  const SectionHeader(
                    title: 'Checkpoints',
                    padding: EdgeInsets.only(top: 16, bottom: 10),
                  ),
                  SizedBox(
                    child: trackingState.checkpoints.isEmpty
                        ? const Align(
                            alignment: Alignment.topCenter,
                            child: EmptyStateCard(
                              icon: Icons.flag_outlined,
                              title: 'No checkpoints',
                              message: 'No checkpoints for this adventure.',
                            ),
                          )
                        : ListView.builder(
                            // Part of the page's scroll, not a scroller of
                            // its own.
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: trackingState.checkpoints.length,
                            itemBuilder: (context, index) {
                              final checkpoint =
                                  trackingState.checkpoints[index];
                              String? distanceText;

                              if (!checkpoint.isReached &&
                                  trackingState.routePoints.isNotEmpty) {
                                final currentPos = LatLng(
                                  trackingState.routePoints.last.latitude,
                                  trackingState.routePoints.last.longitude,
                                );
                                final targetPos = LatLng(
                                  checkpoint.latitude,
                                  checkpoint.longitude,
                                );
                                const dist = Distance();
                                final meters = dist(currentPos, targetPos);

                                // Walking pace, about 5 km/h.
                                final minutes = (meters / 1000 / 5 * 60)
                                    .round();
                                final eta = minutes < 60
                                    ? '$minutes min'
                                    : '${(minutes / 60).toStringAsFixed(1)} h';
                                final km = meters / 1000;

                                distanceText =
                                    '${km.toStringAsFixed(1)} km (~$eta walk)';
                              }

                              return SoftCard(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                radius: 20,
                                child: Row(
                                  children: [
                                    Icon(
                                      checkpoint.isReached
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: checkpoint.isReached
                                          ? AppTheme.emerald
                                          : AppTheme.inkMuted,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            checkpoint.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: AppTheme.ink,
                                            ),
                                          ),
                                          if (distanceText != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              distanceText,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: AppTheme.inkMuted,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '+${checkpoint.xpReward} XP',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.amberText,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            );
            final controls = _ControlButtons(
              session: session,
              onPause: trackingService.pauseAdventure,
              onResume: trackingService.resumeAdventure,
              onFinish: () async {
                final finished = await trackingService.finishAdventure();
                if (context.mounted && finished != null) {
                  _showSummary(context, finished);
                }
              },
              onDiscard: () async {
                await trackingService.discardAdventure();
              },
            );
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('trip-scroll'),
                    child: content,
                  ),
                ),
                const SizedBox(height: 12),
                controls,
              ],
            );
          },
        ),
      ),
    );
  }

  /// "You're here": asks for the proof photo that pays the place's XP.
  void _promptArrivalPhoto(Checkpoint place) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.photo_camera_rounded,
          size: 40,
          color: AppTheme.emerald,
        ),
        title: Text(
          "You're at ${place.name}!",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        content: Text(
          'Take a photo here to confirm your visit and claim '
          '+${place.xpReward} XP. It has to be taken now, with the camera, '
          'while you are at the place.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.inkMuted, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _takeArrivalPhoto(place);
            },
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
          ),
        ],
      ),
    );
  }

  /// Opens the live camera (no gallery) and, if a photo is taken, asks the
  /// trip service whether it proves the visit.
  Future<void> _takeArrivalPhoto(Checkpoint place) async {
    final memory = await Navigator.of(context).push<Memory>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          adventureId: ref.read(trackingServiceProvider).session?.id,
          proofMode: true,
        ),
      ),
    );
    if (memory == null || !mounted) return;
    final sessionId = ref.read(trackingServiceProvider).session?.id;
    if (sessionId != null) {
      ref.invalidate(_adventureMemoriesProvider(sessionId));
    }

    final outcome = await ref
        .read(trackingServiceProvider.notifier)
        .confirmArrivalWithPhoto(memory);
    if (!mounted) return;
    if (outcome.paid) {
      _showArrivedDialog(place.name, outcome);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(outcome.message)));
    }
  }

  void _showArrivedDialog(String placeName, ArrivalOutcome outcome) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.amber,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.amber.withValues(alpha: 0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Icon(
            Icons.celebration_rounded,
            color: AppTheme.ink,
            size: 34,
          ),
        ),
        title: const Text(
          'You made it!',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
        content: Text(
          outcome.xp > 0
              ? "You've arrived at $placeName and earned +${outcome.xp} XP."
              : outcome.message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.inkMuted, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep exploring'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final finished = await ref
                  .read(trackingServiceProvider.notifier)
                  .finishAdventure();
              if (mounted && finished != null) {
                _showSummary(context, finished);
              }
            },
            child: const Text('Finish adventure'),
          ),
        ],
      ),
    );
  }

  void _showSummary(BuildContext context, AdventureSession session) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          session.status == AdventureStatus.unverified
              ? 'Trip not counted'
              : 'Adventure Complete',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session.status == AdventureStatus.unverified)
                TripNotCountedChecklist(
                  session: session,
                  xpNotice: ref.read(trackingServiceProvider).xpNotice,
                )
              else if (ref.read(trackingServiceProvider).xpNotice
                  case final note?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    note,
                    style: const TextStyle(
                      color: AppTheme.amberText,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              SizedBox(
                width: double.maxFinite,
                child: JourneyTrekBreakdown.ofSession(session),
              ),
              const SizedBox(height: 12),
              Text(
                'XP earned: ${session.xpEarned}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.amberText,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (session.status != AdventureStatus.unverified)
            OutlinedButton.icon(
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Share Card'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              onPressed: () {
                Navigator.of(context).pop();
                showTripShareSheet(context, session);
              },
            ),
          FilledButton(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _LiveSharingToggle extends ConsumerWidget {
  const _LiveSharingToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = ref.watch(authStateProvider).value;
    if (!firebaseReady || user == null) return const SizedBox.shrink();

    final trackingState = ref.watch(trackingServiceProvider);
    final trackingService = ref.read(trackingServiceProvider.notifier);

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: SwitchListTile(
        dense: true,
        activeThumbColor: AppTheme.forest,
        title: const Text(
          'Share live location with friends',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink),
        ),
        subtitle: const Text(
          'Only visible to accepted friends. Stops when the adventure ends.',
          style: TextStyle(color: AppTheme.inkMuted),
        ),
        value: trackingState.isSharingLocation,
        onChanged: (value) {
          if (value) {
            trackingService.enableLiveSharing();
          } else {
            trackingService.disableLiveSharing();
          }
        },
      ),
    );
  }
}

class _MemoriesRow extends ConsumerWidget {
  const _MemoriesRow({required this.adventureId});

  final String adventureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoriesAsync = ref.watch(_adventureMemoriesProvider(adventureId));

    return memoriesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (memories) {
        if (memories.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final memory in memories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MetaPill(
                    icon: switch (memory.type) {
                      MemoryType.photo => Icons.photo,
                      MemoryType.video => Icons.videocam,
                      MemoryType.voiceNote => Icons.mic,
                    },
                    label: switch (memory.type) {
                      MemoryType.photo => 'Photo',
                      MemoryType.video => 'Video',
                      MemoryType.voiceNote => 'Voice note',
                    },
                    background: AppTheme.primaryGreen.withValues(alpha: 0.12),
                    foreground: AppTheme.forest,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown briefly while an adventure started from a place is being created.
class _AutoStartView extends ConsumerStatefulWidget {
  const _AutoStartView({
    required this.title,
    required this.checkpoints,
    required this.destination,
    required this.onStarted,
  });

  final String title;
  final List<Checkpoint> checkpoints;
  final Destination? destination;
  final VoidCallback onStarted;

  @override
  ConsumerState<_AutoStartView> createState() => _AutoStartViewState();
}

class _AutoStartViewState extends ConsumerState<_AutoStartView> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onStarted();
      _start();
    });
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await ref
          .read(trackingServiceProvider.notifier)
          .startAdventure(
            title: widget.title,
            checkpoints: widget.checkpoints,
            destination: widget.destination,
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      // Without this the shimmer would stay forever.
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: AppSpacing.page,
        child: Align(
          alignment: Alignment.topCenter,
          child: _error == null
              ? const Shimmer(child: SkeletonBox(height: 150, radius: 32))
              : EmptyStateCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not start the trip',
                  message: 'Something went wrong while starting. Try again.',
                  actionLabel: 'Try again',
                  onAction: _start,
                ),
        ),
      ),
    );
  }
}

/// Rounded tinted banner for in-adventure warnings.
/// Shown while a reached place waits for its proof photo.
class _ArrivalProofCard extends StatelessWidget {
  const _ArrivalProofCard({required this.place, required this.onTakePhoto});

  final String place;
  final VoidCallback onTakePhoto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(
              Icons.photo_camera_rounded,
              color: AppTheme.emerald,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "You're at $place. Take a photo to claim your XP.",
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onTakePhoto,
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              child: const Text('Photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.color,
    required this.icon,
    required this.child,
  });

  final Color color;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ControlButtons extends StatelessWidget {
  const _ControlButtons({
    required this.session,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onDiscard,
  });

  final AdventureSession session;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final isActive = session.status == AdventureStatus.active;
    const shape = StadiumBorder();
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 14);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDiscard,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Discard'),
            style: OutlinedButton.styleFrom(
              shape: shape,
              padding: padding,
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isActive ? onPause : onResume,
            icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
            label: Text(isActive ? 'Pause' : 'Resume'),
            style: OutlinedButton.styleFrom(shape: shape, padding: padding),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.flag),
            label: const Text('Finish'),
            style: FilledButton.styleFrom(shape: shape, padding: padding),
          ),
        ),
      ],
    );
  }
}

enum _StepStatus { done, current, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.number,
    required this.status,
  });

  final DirectionStep step;
  final int number;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final (
      Color background,
      Color foreground,
      IconData icon,
    ) = switch (status) {
      _StepStatus.done => (
        AppTheme.emerald.withValues(alpha: 0.15),
        AppTheme.emerald,
        Icons.check_rounded,
      ),
      _StepStatus.current => (AppTheme.amber, AppTheme.ink, step.icon),
      _StepStatus.upcoming => (
        AppTheme.inkMuted.withValues(alpha: 0.12),
        AppTheme.inkMuted,
        step.icon,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: foreground, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number. ${step.instruction}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: status == _StepStatus.current
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: status == _StepStatus.done
                        ? AppTheme.inkMuted
                        : AppTheme.ink,
                  ),
                ),
                if (step.distanceMeters > 0)
                  Text(
                    'then ${_formatMeters(step.distanceMeters)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMeters(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
