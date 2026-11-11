import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/adventure_session.dart';

class TripNotCountedChecklist extends StatelessWidget {
  const TripNotCountedChecklist({
    super.key,
    required this.session,
    this.xpNotice,
  });

  final AdventureSession session;
  final String? xpNotice;

  static void showHowXpWorksModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.military_tech_rounded,
                  color: AppTheme.amber,
                  size: 28,
                ),
                SizedBox(width: 10),
                Text(
                  'How Tabi XP Works',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ruleItem(
              icon: Icons.directions_walk_rounded,
              title: 'On-foot trek movement',
              description: 'XP is awarded for genuine walking on your trek. The journey taken by car or bus to get there is tracked separately and does not count as trek.',
            ),
            const SizedBox(height: 12),
            _ruleItem(
              icon: Icons.timer_outlined,
              title: 'Minimum 200 m & 3 minutes',
              description: 'A counted trip must cover at least 200 meters of trekking and last at least 3 minutes.',
            ),
            const SizedBox(height: 12),
            _ruleItem(
              icon: Icons.social_distance_rounded,
              title: 'Start distance from places',
              description: 'You must start your adventure from at least 150 meters away from a target destination to count its visit.',
            ),
            const SizedBox(height: 12),
            _ruleItem(
              icon: Icons.camera_alt_outlined,
              title: 'Live photo confirmation',
              description: 'When reaching an undiscovered location, take an authentic live photo with your camera to confirm your discovery.',
            ),
            const SizedBox(height: 12),
            _ruleItem(
              icon: Icons.lock_clock_rounded,
              title: 'Daily fair-play cap',
              description: 'To keep exploration healthy and fair, each explorer can earn up to 500 XP per day from completed trips.',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.forest,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _ruleItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = xpNotice ?? '';
    final hasDistance = session.trekMeters >= 200;
    final hasTime = session.trekSeconds >= 180;
    final noGpsFlag = !note.contains('jump') && !note.contains('mock');
    final notStartedTooClose = !note.contains('started less than');
    final confirmedPhoto = !note.contains('confirmation photo');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppTheme.amberText,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Trip requirements checklist',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppTheme.amberText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _checkRow(
            passed: hasDistance,
            label: 'Walked ≥ 200 m on trek (${session.trekMeters.round()} m)',
          ),
          _checkRow(
            passed: hasTime,
            label:
                'Trek lasted ≥ 3 min (${session.trekSeconds ~/ 60}m ${session.trekSeconds % 60}s)',
          ),
          _checkRow(
            passed: noGpsFlag,
            label: 'Authentic GPS signal without mock jumps',
          ),
          if (!notStartedTooClose)
            _checkRow(
              passed: false,
              label: 'Started > 150 m from destination place',
            ),
          if (!confirmedPhoto)
            _checkRow(passed: false, label: 'Live photo taken at destination'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => showHowXpWorksModal(context),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'How XP works',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryGreen,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppTheme.primaryGreen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkRow({required bool passed, required String label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: passed ? AppTheme.primaryGreen : Colors.red.shade600,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: passed ? FontWeight.w500 : FontWeight.w700,
                color: passed ? AppTheme.ink : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
