import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One marker on the map: a filled disc with a white halo and an icon,
/// inside a 44 px tap area, with an optional corner [badge].
///
/// Every pin has a [label] for screen readers, so meaning never rests on
/// colour alone.
class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
    this.badge,
    this.muted = false,
  });

  /// A place you've been to on a trip.
  factory MapPin.visited({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) => MapPin(
    icon: icon,
    color: AppTheme.primaryGreen,
    label: '$label, visited',
    badge: Icons.check_rounded,
    onTap: onTap,
  );

  /// A place you've saved but not yet found.
  factory MapPin.saved({required String label, VoidCallback? onTap}) => MapPin(
    icon: Icons.bookmark_rounded,
    color: AppTheme.amberText,
    label: '$label, saved',
    onTap: onTap,
  );

  /// A place still under the fog.
  factory MapPin.unknown({VoidCallback? onTap}) => MapPin(
    icon: Icons.question_mark_rounded,
    color: AppTheme.inkMuted,
    label: 'Unknown place',
    muted: true,
    onTap: onTap,
  );

  /// A place to eat (Food layer).
  factory MapPin.food({required String label, VoidCallback? onTap}) => MapPin(
    icon: Icons.restaurant_rounded,
    color: AppTheme.mapFood,
    label: '$label, place to eat',
    onTap: onTap,
  );

  /// A voice note someone left here.
  factory MapPin.voice({required String label, VoidCallback? onTap}) => MapPin(
    icon: Icons.graphic_eq_rounded,
    color: AppTheme.mapVoice,
    label: '$label, voice note',
    onTap: onTap,
  );

  static const double tapSize = 44;
  static const double discSize = 32;

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final IconData? badge;

  /// Drawn lighter: for places you can't see yet.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).colorScheme.onPrimary;
    final halo = Theme.of(context).colorScheme.surface;
    final disc = Container(
      width: discSize,
      height: discSize,
      decoration: BoxDecoration(
        color: muted ? halo : color,
        shape: BoxShape.circle,
        border: Border.all(color: muted ? color : halo, width: 2),
        boxShadow: AppElevation.level1,
      ),
      child: Icon(icon, size: 18, color: muted ? color : onColor),
    );
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: tapSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              disc,
              if (badge != null)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: halo, width: 1.5),
                    ),
                    child: Icon(badge, size: 10, color: AppTheme.ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
