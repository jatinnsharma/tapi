import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/adventure_session.dart';

Future<void> showTripShareSheet(
  BuildContext context,
  AdventureSession session,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _TripShareSheet(session: session),
  );
}

class _TripShareSheet extends StatelessWidget {
  const _TripShareSheet({required this.session});

  final AdventureSession session;

  String _generateShareText() {
    final trekKm = (session.trekMeters / 1000).toStringAsFixed(1);
    final durationMins = (session.durationSeconds / 60).round();
    final steps = session.trekSteps > 0 ? session.trekSteps : session.steps;

    final stepLine = steps > 0
        ? '👟 Steps: ${NumberFormat('#,###').format(steps)}\n'
        : '';

    return '🧭 Explored "${session.title}" with Tabi!\n'
        '🚶 Trek: $trekKm km\n'
        '⏱ Duration: $durationMins mins\n'
        '$stepLine'
        '⚡ XP Earned: +${session.xpEarned} XP\n\n'
        '#TabiApp #RealWorldExploration #Chandigarh';
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _generateShareText()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Trip summary copied to clipboard! Ready to share on WhatsApp or Instagram.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.share_rounded, color: AppTheme.forest, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Share Adventure',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Share Card Preview
          TripShareCard(session: session),
          const SizedBox(height: 20),
          // Action Buttons
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _copyToClipboard(context),
              icon: const Icon(Icons.copy_rounded, size: 20),
              label: const Text(
                'Copy Share Text',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tip: Take a screenshot of the card above to post directly to your Instagram story!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.inkMuted),
          ),
        ],
      ),
    );
  }
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
            'Adventure Completed · Chandigarh',
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
