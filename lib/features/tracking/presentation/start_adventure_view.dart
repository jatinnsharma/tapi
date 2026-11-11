import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../weather/application/weather_service.dart';
import '../../weather/domain/weather_model.dart';
import '../application/tracking_service.dart';
import '../domain/checkpoint.dart';
import '../domain/directions.dart';
import '../domain/trip_guard.dart';
import '../domain/trip_split.dart';

/// Before a trip: name it, see how it will count, and start.
class StartAdventureView extends ConsumerStatefulWidget {
  const StartAdventureView({
    super.key,
    required this.title,
    this.checkpointTemplates = const [],
    this.destination,
  });

  final String title;
  final List<Checkpoint> checkpointTemplates;
  final Destination? destination;

  @override
  ConsumerState<StartAdventureView> createState() => _StartAdventureViewState();
}

class _StartAdventureViewState extends ConsumerState<StartAdventureView> {
  late final _name = TextEditingController(text: widget.title);
  bool _starting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    HapticFeedback.mediumImpact();
    final name = _name.text.trim();
    try {
      await ref
          .read(trackingServiceProvider.notifier)
          .startAdventure(
            title: name.isEmpty ? widget.title : name,
            checkpoints: widget.checkpointTemplates,
            destination: widget.destination,
          );
    } catch (_) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    return Scaffold(
      appBar: AppBar(title: const Text('New adventure')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          FadeSlideIn(
            child: _ReadyCard(
              name: _name,
              destination: destination,
              starting: _starting,
              onStart: _start,
            ),
          ),
          const SizedBox(height: 18),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: _HowItCounts(destination: destination),
          ),
          const SizedBox(height: 18),
          const FadeSlideIn(
            delay: Duration(milliseconds: 160),
            child: _WhatsTracked(),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppTheme.inkMuted,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pause any time. Your route stays on this phone unless '
                  'you choose to share it.',
                  style: TextStyle(color: AppTheme.inkMuted, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The hero: a name for the trip, where it goes, the weather, and the big
/// start button.
class _ReadyCard extends ConsumerWidget {
  const _ReadyCard({
    required this.name,
    required this.destination,
    required this.starting,
    required this.onStart,
  });

  final TextEditingController name;
  final Destination? destination;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(currentWeatherProvider).value;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _GlassChip(
                icon: Icons.auto_awesome_rounded,
                label: 'Ready to explore',
                iconColor: AppTheme.amber,
              ),
              const Spacer(),
              if (weather != null) _WeatherChip(weather: weather),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'NAME YOUR ADVENTURE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          TextField(
            key: const ValueKey('adventure-name'),
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            cursorColor: AppTheme.amber,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              suffixIcon: Icon(
                Icons.edit_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.amber, width: 2),
              ),
              border: const UnderlineInputBorder(),
            ),
          ),
          if (destination != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.flag_rounded, size: 17, color: AppTheme.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Heading to ${destination!.name} · +${destination!.xpReward} XP',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          Center(
            child: _StartButton(starting: starting, onPressed: onStart),
          ),
          const SizedBox(height: 12),
          Text(
            starting ? 'Starting…' : 'Tap to start tracking',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A big amber start button with soft pulsing rings. The pulse stops when the
/// phone asks for reduced motion.
class _StartButton extends StatefulWidget {
  const _StartButton({required this.starting, required this.onPressed});

  final bool starting;
  final VoidCallback onPressed;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  static const _size = 128.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start tracking',
      excludeSemantics: true,
      child: SizedBox(
        width: _size * 1.6,
        height: _size * 1.6,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Two rings expanding out of the button, half a cycle apart.
            for (final offset in const [0.0, 0.5])
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = (_pulse.value + offset) % 1.0;
                  return Container(
                    width: _size * (1 + 0.55 * t),
                    height: _size * (1 + 0.55 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.amber.withValues(alpha: 0.55 * (1 - t)),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            PressableScale(
              child: GestureDetector(
                key: const ValueKey('start-button'),
                onTap: widget.starting ? null : widget.onPressed,
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFD166), AppTheme.amber],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.amber.withValues(alpha: 0.55),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: widget.starting
                      ? const Center(
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              color: AppTheme.ink,
                              strokeWidth: 3,
                            ),
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              size: 52,
                              color: AppTheme.ink,
                            ),
                            Text(
                              'START',
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.icon,
    required this.label,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({required this.weather});
  final WeatherData weather;

  IconData get _icon {
    final c = weather.weatherCode;
    if (c == 0) {
      return weather.isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    }
    if (c <= 3) return Icons.wb_cloudy_rounded;
    if (c == 45 || c == 48) return Icons.foggy;
    if (c >= 95) return Icons.thunderstorm_rounded;
    if (c >= 71 && c <= 75) return Icons.ac_unit_rounded;
    return Icons.water_drop_rounded;
  }

  @override
  Widget build(BuildContext context) => _GlassChip(
    icon: _icon,
    label: '${weather.temperature.round()}°C',
    iconColor: weather.isSevere ? Colors.redAccent : AppTheme.amber,
  );
}

/// How the trip will count, as a short timeline.
class _HowItCounts extends StatelessWidget {
  const _HowItCounts({required this.destination});
  final Destination? destination;

  @override
  Widget build(BuildContext context) {
    final place = destination?.name;
    final radius = TripSplit.trekStartRadiusMeters.round();
    final steps = <(IconData, String, String)>[
      if (place != null)
        (
          Icons.directions_car_filled_rounded,
          'Journey',
          'Get near $place any way you like: walk, car or bus. '
              "It's shown separately and isn't counted as trek.",
        ),
      (
        Icons.hiking_rounded,
        'Trek',
        place != null
            ? 'Starts within $radius m of $place. Your distance, time and '
                  'steps on foot count from there.'
            : 'Starts right away. Your distance, time and steps on foot '
                  'count.',
      ),
      if (place != null)
        (
          Icons.photo_camera_rounded,
          'Proof photo',
          'At $place, take a live photo to earn its '
              '+${destination!.xpReward} XP.',
        ),
      (
        Icons.flag_rounded,
        'Finish',
        'Trek at least ${TripGuard.minCompletionMeters} m for '
            '${TripGuard.minCompletionSeconds ~/ 60} minutes to earn the '
            '+100 XP completion bonus.',
      ),
    ];

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How your trip counts',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            _TimelineStep(
              number: i + 1,
              icon: steps[i].$1,
              title: steps[i].$2,
              body: steps[i].$3,
              isLast: i == steps.length - 1,
              highlight: steps[i].$2 == 'Trek',
            ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.isLast,
    required this.highlight,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppTheme.emerald : AppTheme.forest;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: highlight
                      ? const LinearGradient(
                          colors: [AppTheme.emerald, AppTheme.primaryGreen],
                        )
                      : null,
                  color: highlight ? null : color.withValues(alpha: 0.1),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: highlight ? Colors.white : color,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppTheme.forest.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$number. $title',
                    style: TextStyle(
                      color: highlight ? AppTheme.primaryGreen : AppTheme.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppTheme.inkMuted,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the app records during the trip.
class _WhatsTracked extends StatelessWidget {
  const _WhatsTracked();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.route_rounded, 'Live route', 'On the map'),
      (Icons.directions_walk_rounded, 'Steps', 'Step sensor'),
      (Icons.photo_library_rounded, 'Memories', 'Photo · video · voice'),
      (Icons.screen_lock_portrait_rounded, 'Screen off', 'Keeps tracking'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "What's tracked",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            for (final (icon, title, sub) in items)
              SoftCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                radius: 18,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
