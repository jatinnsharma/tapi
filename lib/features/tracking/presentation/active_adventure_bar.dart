import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../application/tracking_service.dart';
import '../domain/adventure_session.dart';

/// While a trip runs (or is paused), a slim bar above the tabs on every tab:
/// time and distance, tap to go back to the trip, and SOS one tap away.
/// Hidden when there's no trip.
class ActiveAdventureBar extends ConsumerWidget {
  const ActiveAdventureBar({super.key});

  static String formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String formatKm(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackingServiceProvider);
    final session = state.session;
    if (session == null ||
        (session.status != AdventureStatus.active &&
            session.status != AdventureStatus.paused)) {
      return const SizedBox.shrink();
    }
    final paused = session.status == AdventureStatus.paused;
    final colors = AppColors.of(context);
    // White on the dark brand bar.
    final onBar = Theme.of(context).colorScheme.onPrimary;
    final text = Theme.of(context).textTheme;
    final tabular = const [FontFeature.tabularFigures()];

    return Material(
      color: AppTheme.forest,
      child: SafeArea(
        top: false,
        bottom: false,
        child: InkWell(
          onTap: () => context.push('/tracking'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  paused ? Icons.pause_circle_outline : Icons.directions_walk,
                  color: onBar,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    label: paused ? 'Trip paused' : 'Trip in progress',
                    child: Text(
                      '${paused ? 'Paused' : 'On a trip'} · '
                      '${formatElapsed(state.elapsed)} · '
                      '${formatKm(session.distanceMeters)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(
                        color: onBar,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/tracking'),
                  style: TextButton.styleFrom(foregroundColor: onBar),
                  child: Text(paused ? 'Resume' : 'Open'),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Safety and SOS',
                  child: FilledButton(
                    onPressed: () => context.push('/safety'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.danger,
                      foregroundColor: onBar,
                      minimumSize: const Size(64, 48),
                    ),
                    child: const Text('SOS'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
