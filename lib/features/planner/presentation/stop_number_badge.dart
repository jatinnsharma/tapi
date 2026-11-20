import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A stop's number, or a tick once it's done. Used in the timeline and on
/// the map so the two match.
class StopNumberBadge extends StatelessWidget {
  const StopNumberBadge({
    super.key,
    required this.number,
    required this.done,
    this.size = 32,
    this.highlight = false,
  });

  final int number;
  final bool done;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final fill = done
        ? colors.textSecondary
        : (highlight ? scheme.primary : AppTheme.forest);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: done
          ? Icon(Icons.check_rounded, size: size * 0.5, color: scheme.onPrimary)
          : Text(
              '$number',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onPrimary),
            ),
    );
  }
}
