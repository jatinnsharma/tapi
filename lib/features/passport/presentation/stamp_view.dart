import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/passport_stamp.dart';

/// Ink colour and symbol of a stamp, from the kind of city.
({Color ink, IconData icon, String motto}) stampStyle(
  String category,
) => switch (category) {
  'heritage' => (
    ink: const Color(0xFF8E2C2C),
    icon: Icons.account_balance,
    motto: 'HERITAGE',
  ),
  'spiritual' => (
    ink: const Color(0xFFB8560F),
    icon: Icons.temple_hindu,
    motto: 'PILGRIM',
  ),
  'hill_station' => (
    ink: const Color(0xFF1F5F7A),
    icon: Icons.landscape,
    motto: 'HILLS',
  ),
  'beach' || 'coastal' => (
    ink: const Color(0xFF0E6E8C),
    icon: Icons.sailing,
    motto: 'COAST',
  ),
  'nature' => (ink: const Color(0xFF2E6B3A), icon: Icons.forest, motto: 'WILD'),
  'adventure' => (
    ink: const Color(0xFFA6431B),
    icon: Icons.hiking,
    motto: 'ADVENTURE',
  ),
  _ => (ink: const Color(0xFF3A3F8F), icon: Icons.location_city, motto: 'CITY'),
};

/// A round, slightly tilted rubber stamp: city, state, date and serial.
class StampView extends StatelessWidget {
  const StampView({super.key, required this.stamp, this.size = 150});

  final PassportStamp stamp;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = stampStyle(stamp.city.category);
    // Each stamp leans its own way, like real ones; same stamp, same angle.
    final tilt = _stableTiltDegrees(stamp.city.id) * math.pi / 180;

    return Semantics(
      label:
          '${stamp.city.name} stamp, ${stamp.serialLabel}, earned '
          '${DateFormat.yMMMd().format(stamp.earnedAt)}',
      child: ExcludeSemantics(
        child: Transform.rotate(
          angle: tilt,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _StampRingsPainter(style.ink),
              child: Padding(
                padding: EdgeInsets.all(size * 0.17),
                child: FittedBox(
                  child: SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          stamp.city.state.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: style.ink,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Icon(style.icon, color: style.ink, size: 26),
                        Text(
                          stamp.city.name.toUpperCase(),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: style.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d MMM yyyy').format(stamp.earnedAt),
                          style: TextStyle(
                            color: style.ink,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${style.motto} · ${stamp.serialLabel}',
                          style: TextStyle(
                            color: style.ink.withValues(alpha: 0.8),
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// -6° to +6°, the same for a city on every run (unlike `String.hashCode`,
/// which may change between runs).
int _stableTiltDegrees(String id) =>
    id.codeUnits.fold<int>(0, (sum, c) => (sum * 31 + c) % 9973) % 13 - 6;

/// A solid outer ring, a dotted inner ring, and a faint ink wash.
class _StampRingsPainter extends CustomPainter {
  _StampRingsPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      center,
      radius * 0.96,
      Paint()..color = ink.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      center,
      radius * 0.94,
      Paint()
        ..color = ink.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.05,
    );

    final dot = Paint()..color = ink.withValues(alpha: 0.75);
    const dots = 48;
    for (var i = 0; i < dots; i++) {
      final angle = 2 * math.pi * i / dots;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.82,
        radius * 0.018,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_StampRingsPainter old) => old.ink != ink;
}
