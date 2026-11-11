import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/adventure_session.dart';
import '../domain/trip_split.dart';

/// Journey and trek side by side, with how the time split between them, the
/// total trip time and the trek's difficulty (from the trek alone). Used live
/// on the trip, in the finish summary and in the journal, so all three agree.
class JourneyTrekBreakdown extends StatelessWidget {
  const JourneyTrekBreakdown({
    super.key,
    required this.journeyMeters,
    required this.journeyTime,
    required this.trekMeters,
    required this.trekTime,
    required this.totalTime,
    this.onDark = false,
    this.steps,
    this.trekSteps,
  });

  JourneyTrekBreakdown.ofSession(
    AdventureSession session, {
    super.key,
    this.onDark = false,
  }) : journeyMeters = session.journeyMeters,
       journeyTime = Duration(seconds: session.journeySeconds),
       trekMeters = session.trekMeters,
       trekTime = Duration(seconds: session.trekSeconds),
       totalTime = Duration(seconds: session.durationSeconds),
       // Older trips, and phones without a step sensor, have no steps.
       steps = session.steps > 0 ? session.steps : null,
       trekSteps = session.steps > 0 ? session.trekSteps : null;

  final double journeyMeters;
  final Duration journeyTime;
  final double trekMeters;
  final Duration trekTime;
  final Duration totalTime;

  /// For the dark hero card on the live trip screen.
  final bool onDark;

  /// Steps from the step sensor; null when there are none to show.
  final int? steps;
  final int? trekSteps;

  @override
  Widget build(BuildContext context) {
    final difficulty = TrekDifficulty.forTrek(trekMeters);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PartTile(
                  key: const ValueKey('journey'),
                  icon: Icons.directions_car_filled_rounded,
                  label: 'Journey',
                  hint: 'Getting there & back',
                  meters: journeyMeters,
                  time: journeyTime,
                  steps: steps == null
                      ? null
                      : (steps! - (trekSteps ?? 0)).clamp(0, steps!),
                  style: onDark ? _TileStyle.glass : _TileStyle.plain,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PartTile(
                  key: const ValueKey('trek'),
                  icon: Icons.hiking_rounded,
                  label: 'Trek',
                  hint: 'On foot from the start',
                  meters: trekMeters,
                  time: trekTime,
                  steps: trekSteps,
                  style: onDark ? _TileStyle.amberGlass : _TileStyle.emerald,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _TimeShareBar(journey: journeyTime, trek: trekTime, onDark: onDark),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              key: const ValueKey('total'),
              icon: Icons.timer_outlined,
              text: 'Total trip: ${formatTripDuration(totalTime)}',
              color: onDark ? Colors.white : AppTheme.forest,
              onDark: onDark,
            ),
            _Chip(
              key: const ValueKey('difficulty'),
              icon: Icons.terrain_rounded,
              text: difficulty == null
                  ? 'Difficulty: no trek yet'
                  : 'Trek difficulty: ${difficulty.label}',
              color: difficulty == null
                  ? (onDark ? Colors.white70 : AppTheme.inkMuted)
                  : difficultyColor(difficulty),
              onDark: onDark,
            ),
          ],
        ),
      ],
    );
  }
}

enum _TileStyle { plain, emerald, glass, amberGlass }

class _PartTile extends StatelessWidget {
  const _PartTile({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.meters,
    required this.time,
    required this.style,
    this.steps,
  });

  final IconData icon;
  final String label;
  final String hint;
  final double meters;
  final Duration time;
  final _TileStyle style;
  final int? steps;

  @override
  Widget build(BuildContext context) {
    final (
      Decoration box,
      Color fg,
      Color muted,
      Color badge,
      Color badgeFg,
    ) = switch (style) {
      _TileStyle.plain => (
        BoxDecoration(
          color: AppTheme.forest.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.forest.withValues(alpha: 0.08)),
        ),
        AppTheme.ink,
        AppTheme.inkMuted,
        AppTheme.forest.withValues(alpha: 0.09),
        AppTheme.forest,
      ),
      _TileStyle.emerald => (
        BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.emerald, AppTheme.primaryGreen],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.emerald.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        Colors.white,
        Colors.white.withValues(alpha: 0.82),
        Colors.white.withValues(alpha: 0.2),
        Colors.white,
      ),
      _TileStyle.glass => (
        BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        Colors.white,
        Colors.white.withValues(alpha: 0.7),
        Colors.white.withValues(alpha: 0.14),
        Colors.white,
      ),
      _TileStyle.amberGlass => (
        BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.amber.withValues(alpha: 0.30),
              AppTheme.amber.withValues(alpha: 0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.amber.withValues(alpha: 0.45)),
        ),
        Colors.white,
        Colors.white.withValues(alpha: 0.75),
        AppTheme.amber,
        AppTheme.ink,
      ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                child: Icon(icon, size: 17, color: badgeFg),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatTripDistance(meters),
              style: TextStyle(
                color: fg,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  formatTripDuration(time),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (steps case final n?) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.directions_walk_rounded, size: 14, color: muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    formatSteps(n),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            hint,
            style: TextStyle(color: muted, fontSize: 11.5, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// A slim two-colour bar: how the moving time split between journey and
/// trek.
class _TimeShareBar extends StatelessWidget {
  const _TimeShareBar({
    required this.journey,
    required this.trek,
    required this.onDark,
  });

  final Duration journey;
  final Duration trek;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final total = journey.inSeconds + trek.inSeconds;
    final trekShare = total == 0 ? 0.0 : trek.inSeconds / total;
    final journeyColor = onDark
        ? Colors.white.withValues(alpha: 0.35)
        : AppTheme.forest.withValues(alpha: 0.18);
    final trekColor = onDark ? AppTheme.amber : AppTheme.emerald;
    final muted = onDark
        ? Colors.white.withValues(alpha: 0.75)
        : AppTheme.inkMuted;
    final pct = (trekShare * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: total == 0
                ? ColoredBox(color: journeyColor)
                : Row(
                    // Stretch: an empty ColoredBox is otherwise 0 px tall.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (trekShare < 1)
                        Expanded(
                          flex: ((1 - trekShare) * 1000).round(),
                          child: ColoredBox(color: journeyColor),
                        ),
                      if (trekShare > 0)
                        Expanded(
                          flex: (trekShare * 1000).round(),
                          child: ColoredBox(color: trekColor),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          total == 0
              ? 'No moving time yet'
              : '$pct% of your moving time was trek',
          key: const ValueKey('share'),
          style: TextStyle(color: muted, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    required this.onDark,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: onDark ? Colors.white : color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Green for easy, through amber and orange, to red for hard.
Color difficultyColor(TrekDifficulty d) => switch (d) {
  TrekDifficulty.easy => AppTheme.emerald,
  TrekDifficulty.moderate => AppTheme.amberText,
  TrekDifficulty.challenging => const Color(0xFFE8590C),
  TrekDifficulty.hard => const Color(0xFFD63031),
};

/// "1 step", "1,240 steps".
String formatSteps(int steps) {
  final digits = steps.toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return steps == 1 ? '1 step' : '$grouped steps';
}

/// "850 m" under a kilometre, else "3.42 km".
String formatTripDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(2)} km';

/// "0 min", "<1 min", "12 min", "1h 05m".
String formatTripDuration(Duration d) {
  if (d == Duration.zero) return '0 min';
  if (d.inMinutes < 1) return '<1 min';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}
