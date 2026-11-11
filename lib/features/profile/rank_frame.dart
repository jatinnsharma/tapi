import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/rank_style_service.dart';
import 'domain/rank_style.dart';

/// A gradient ring in the equipped rank style's colours around [child].
class RankFrame extends ConsumerWidget {
  const RankFrame({super.key, required this.child, this.style});

  final Widget child;

  /// Show this style instead of the equipped one (used by the ladder).
  final RankStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown =
        style ??
        ref.watch(rankStyleProvider).value?.equipped ??
        rankStyles.first;
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [...shown.frame, shown.frame.first]),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: child,
      ),
    );
  }
}
