import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/weather_advisory.dart';

/// "Thunderstorm nearby — 6 exposed places hidden. Show all": tells the user
/// a list is filtered for the weather, and lets them undo it.
class WeatherAdvisoryBanner extends StatelessWidget {
  const WeatherAdvisoryBanner({
    super.key,
    required this.advisory,
    required this.hiddenCount,
    required this.showingAll,
    required this.onToggle,
  });

  final WeatherAdvisory advisory;

  /// Places left out by [advisory] (0 when [showingAll]).
  final int hiddenCount;
  final bool showingAll;
  final VoidCallback onToggle;

  IconData get _icon => switch (advisory.kind) {
    AdvisoryKind.storm => Icons.thunderstorm_outlined,
    AdvisoryKind.heavyRain => Icons.water_drop_outlined,
    AdvisoryKind.extremeHeat => Icons.wb_sunny_outlined,
    AdvisoryKind.poorAir => Icons.masks_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final detail = showingAll
        ? 'Showing every place, whatever the weather.'
        : hiddenCount == 0
        ? advisory.advice
        : '${advisory.advice} '
              '$hiddenCount ${hiddenCount == 1 ? 'place' : 'places'} hidden.';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(_icon, color: AppTheme.amberText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  advisory.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (showingAll || hiddenCount > 0)
            TextButton(
              onPressed: onToggle,
              child: Text(showingAll ? 'Hide unsuitable' : 'Show all'),
            ),
        ],
      ),
    );
  }
}
