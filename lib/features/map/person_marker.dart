import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/theme/app_theme.dart';
import '../../core/theme/components.dart';
import '../auth/application/auth_service.dart';
import '../profile/rank_frame.dart';

/// Size of [personMarker]: the avatar plus the pointer under it.
const personMarkerSize = Size(56, 66);

/// "You are here" on a map: your avatar in your rank frame, with a pointer
/// to the exact spot and a soft halo.
Marker personMarker(LatLng point, {Key? key}) => Marker(
  key: key,
  point: point,
  width: personMarkerSize.width,
  height: personMarkerSize.height,
  // The pointer's tip sits on the point.
  alignment: Alignment.topCenter,
  child: const PersonMarker(),
);

class PersonMarker extends ConsumerWidget {
  const PersonMarker({super.key, this.initial});

  /// Letter shown in the avatar; defaults to the signed-in user's.
  final String? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var letter = initial;
    if (letter == null) {
      try {
        final user = ref.watch(authStateProvider).value;
        letter = user?.displayName ?? user?.email;
      } catch (_) {
        // Firebase not set up (offline build, tests): no letter.
      }
    }

    return Semantics(
      label: 'You are here',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.emerald.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: RankFrame(
              child: letter == null || letter.isEmpty
                  ? Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.forest, AppTheme.emerald],
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    )
                  : AppAvatar(initial: letter, size: 36),
            ),
          ),
          CustomPaint(size: const Size(14, 9), painter: _PointerPainter()),
        ],
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Where a trip began: a small green "Start" pin.
Marker startMarker(LatLng point) => Marker(
  point: point,
  width: 70,
  height: 34,
  alignment: Alignment.topCenter,
  child: const StartPin(),
);

class StartPin extends StatelessWidget {
  const StartPin({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Trip start',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.emerald,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.forest.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                SizedBox(width: 2),
                Text(
                  'Start',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 2, height: 6, color: AppTheme.emerald),
        ],
      ),
    );
  }
}
