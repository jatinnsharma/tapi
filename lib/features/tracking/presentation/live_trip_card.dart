import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../domain/adventure_session.dart';
import '../domain/trip_split.dart';
import 'journey_trek_breakdown.dart';

/// The trip's live card: where you are in the trip (journey, trek, back),
/// how close the trek start is, and journey vs trek so far.
class LiveTripCard extends StatelessWidget {
  const LiveTripCard({
    super.key,
    required this.session,
    required this.elapsed,
    required this.phase,
    required this.metersToTrekStart,
    required this.placeName,
    this.stepsCounting = false,
  });

  /// Whether the step sensor is reporting: steps are shown from then on.
  final bool stepsCounting;

  final AdventureSession session;
  final Duration elapsed;
  final TripPhase phase;
  final double? metersToTrekStart;
  final String? placeName;

  @override
  Widget build(BuildContext context) {
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      radius: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _PhaseSteps(phase: phase)),
              const SizedBox(width: 10),
              _XpBadge(xp: session.xpEarned),
            ],
          ),
          const SizedBox(height: 14),
          _PhaseMessage(
            phase: phase,
            metersToTrekStart: metersToTrekStart,
            journeyMeters: session.journeyMeters,
            placeName: placeName,
          ),
          const SizedBox(height: 14),
          JourneyTrekBreakdown(
            journeyMeters: session.journeyMeters,
            journeyTime: Duration(seconds: session.journeySeconds),
            trekMeters: session.trekMeters,
            trekTime: Duration(seconds: session.trekSeconds),
            totalTime: elapsed,
            onDark: true,
            steps: stepsCounting || session.steps > 0 ? session.steps : null,
            trekSteps: stepsCounting || session.steps > 0
                ? session.trekSteps
                : null,
          ),
        ],
      ),
    );
  }
}

/// Journey → Trek → Back, with the current step lit.
class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({required this.phase});

  final TripPhase phase;

  @override
  Widget build(BuildContext context) {
    final current = TripPhase.values.indexOf(phase);
    const steps = [
      (Icons.directions_car_filled_rounded, 'Journey'),
      (Icons.hiking_rounded, 'Trek'),
      (Icons.home_rounded, 'Back'),
    ];
    return Row(
      key: const ValueKey('phase'),
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: i <= current
                      ? AppTheme.amber.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          _Step(
            icon: steps[i].$1,
            label: steps[i].$2,
            state: i < current
                ? _StepState.done
                : (i == current ? _StepState.now : _StepState.later),
            highlight: i == 1,
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, now, later }

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.state,
    required this.highlight,
  });

  final IconData icon;
  final String label;
  final _StepState state;

  /// The trek step glows amber when current.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final now = state == _StepState.now;
    final background = switch (state) {
      _StepState.now => highlight ? AppTheme.amber : Colors.white,
      _StepState.done => Colors.white.withValues(alpha: 0.18),
      _StepState.later => Colors.transparent,
    };
    final foreground = switch (state) {
      _StepState.now => AppTheme.forest,
      _StepState.done => Colors.white,
      _StepState.later => Colors.white.withValues(alpha: 0.55),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(horizontal: now ? 10 : 7, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: state == _StepState.later
            ? Border.all(color: Colors.white.withValues(alpha: 0.25))
            : null,
        boxShadow: now
            ? [
                BoxShadow(
                  color: (highlight ? AppTheme.amber : Colors.white).withValues(
                    alpha: 0.35,
                  ),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state == _StepState.done ? Icons.check_rounded : icon,
            size: 15,
            color: foreground,
          ),
          if (now) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _XpBadge extends StatelessWidget {
  const _XpBadge({required this.xp});
  final int xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC94D), AppTheme.amber],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.ink),
          const SizedBox(width: 2),
          Text(
            '+$xp XP',
            style: const TextStyle(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the current phase means, with a progress bar toward the trek start.
class _PhaseMessage extends StatelessWidget {
  const _PhaseMessage({
    required this.phase,
    required this.metersToTrekStart,
    required this.journeyMeters,
    required this.placeName,
  });

  final TripPhase phase;
  final double? metersToTrekStart;
  final double journeyMeters;
  final String? placeName;

  @override
  Widget build(BuildContext context) {
    const title = TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    );
    final sub = TextStyle(
      color: Colors.white.withValues(alpha: 0.75),
      fontSize: 12.5,
      height: 1.3,
    );

    switch (phase) {
      case TripPhase.toTrekStart:
        final away = metersToTrekStart;
        final toZone = away == null
            ? null
            : (away - TripSplit.trekStartRadiusMeters).clamp(
                0.0,
                double.infinity,
              );
        final progress = toZone == null || journeyMeters + toZone == 0
            ? null
            : journeyMeters / (journeyMeters + toZone);
        return Column(
          key: const ValueKey('phase-message'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              toZone == null
                  ? 'On the journey'
                  : 'Trek starts in ${formatTripDistance(toZone)}',
              style: title,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: AppTheme.amber,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              placeName == null
                  ? 'Any transport is fine until the trek starts.'
                  : 'The trek begins within '
                        '${TripSplit.trekStartRadiusMeters.round()} m of '
                        '$placeName. Any transport is fine until then.',
              style: sub,
            ),
          ],
        );
      case TripPhase.trekking:
        return Column(
          key: const ValueKey('phase-message'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("You're trekking", style: title),
            const SizedBox(height: 3),
            Text(
              'Every step on foot counts toward your trek, '
              'including the walk back.',
              style: sub,
            ),
          ],
        );
      case TripPhase.returning:
        return Column(
          key: const ValueKey('phase-message'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Heading back', style: title),
            const SizedBox(height: 3),
            Text(
              'Travel home counts as journey. Finish the trip when '
              "you're done.",
              style: sub,
            ),
          ],
        );
    }
  }
}
