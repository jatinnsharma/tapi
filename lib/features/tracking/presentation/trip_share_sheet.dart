import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/share_card.dart';
import '../domain/adventure_session.dart';

Future<void> showTripShareSheet(
  BuildContext context,
  AdventureSession session,
) {
  return showShareCardSheet(
    context,
    title: 'Share trip',
    card: TripShareCard(session: session),
    fileName: 'trip-${session.id}.png',
    shareText: '${session.title} · explored with Tabi',
    copyText: tripSummaryText(session),
  );
}

/// The trip in a few plain lines, for pasting into a message.
String tripSummaryText(AdventureSession session) {
  final km = (session.trekMeters / 1000).toStringAsFixed(1);
  final minutes = (session.durationSeconds / 60).round();
  final steps = session.trekSteps > 0 ? session.trekSteps : session.steps;
  return [
    'Explored "${session.title}" with Tabi',
    '$km km on foot · $minutes min',
    if (steps > 0) '${NumberFormat.decimalPattern().format(steps)} steps',
    if (session.xpEarned > 0) '+${session.xpEarned} XP',
  ].join('\n');
}

class TripShareCard extends StatelessWidget {
  const TripShareCard({super.key, required this.session});

  final AdventureSession session;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMMM yyyy')
        .format(session.startedAt.toLocal());
    final trekKm = (session.trekMeters / 1000).toStringAsFixed(1);
    final durationMins = (session.durationSeconds / 60).round();
    final steps = session.trekSteps > 0 ? session.trekSteps : session.steps;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A2F), Color(0xFF0F1E19)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.emerald.withValues(alpha: 0.2),
                    ),
                    child: const Icon(
                      Icons.explore_rounded,
                      color: AppTheme.emerald,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TABI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Text(
                dateStr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Title
          Text(
            session.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adventure Completed',
            style: TextStyle(
              color: AppTheme.emerald.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          // Stats Grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.directions_walk_rounded,
                  label: 'Trek',
                  value: '$trekKm km',
                ),
                _StatItem(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: '${durationMins}m',
                ),
                if (steps > 0)
                  _StatItem(
                    icon: Icons.nordic_walking_rounded,
                    label: 'Steps',
                    value: NumberFormat('#,###').format(steps),
                  ),
                _StatItem(
                  icon: Icons.bolt_rounded,
                  label: 'XP Earned',
                  value: '+${session.xpEarned}',
                  valueColor: AppTheme.amber,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Tagline Footer
          Center(
            child: Text(
              'Real-World Exploration · Discover Hidden Gems',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: valueColor ?? Colors.white.withValues(alpha: 0.8),
          size: 18,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
