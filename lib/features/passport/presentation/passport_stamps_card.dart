import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../application/passport_service.dart';

/// Passport tab entry to the stamps: how many cities, and the latest one.
class PassportStampsCard extends ConsumerWidget {
  const PassportStampsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stamps = ref.watch(passportStampsProvider).value;
    final count = stamps?.length ?? 0;
    final subtitle = stamps == null
        ? 'Loading…'
        : count == 0
        ? 'Reach a place on a trip to earn your first city stamp.'
        : 'Latest: ${stamps.last.city.name}';

    return SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('/passport-stamps'),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.approval_rounded,
              color: AppTheme.forest,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 0
                      ? 'Passport stamps'
                      : '$count ${count == 1 ? 'city' : 'cities'} stamped',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.inkMuted),
        ],
      ),
    );
  }
}
