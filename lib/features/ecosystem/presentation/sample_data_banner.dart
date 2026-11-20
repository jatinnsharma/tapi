import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A strip under the app bar of every ecosystem screen saying the listings
/// are samples.
///
/// The ecosystem screens (guides, gear, events, stays, transport, rewards,
/// creator mode) run on hard-coded sample data, not real listings, prices or
/// points. They are hidden in release behind `FeatureFlags.ecosystem`; this
/// banner keeps them honest if the flag is ever turned on before real data
/// sources exist.
class SampleDataBanner extends StatelessWidget implements PreferredSizeWidget {
  const SampleDataBanner({super.key});

  static const message =
      'Preview with sample data: these listings, prices and points are '
      'not real and cannot be booked or redeemed.';

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          height: preferredSize.height,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: AppTheme.amber.withValues(alpha: 0.22),
          child: const Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: AppTheme.amberText),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.amberText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
