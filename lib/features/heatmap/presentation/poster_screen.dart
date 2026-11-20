import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/theme/app_components.dart';
import '../../../core/ui/share_card.dart';
import '../../auth/application/display_name_provider.dart';
import '../application/heatmap_service.dart';
import '../domain/route_art.dart';

/// Pixel ratio of the exported poster: a 360-wide poster becomes 1440 px.
const posterPixelRatio = 4.0;

/// Turns the user's routes into a shareable line-art poster.
class PosterScreen extends ConsumerStatefulWidget {
  const PosterScreen({super.key, required this.footprint});

  final ExplorationFootprint footprint;

  @override
  ConsumerState<PosterScreen> createState() => _PosterScreenState();
}

class _PosterScreenState extends ConsumerState<PosterScreen> {
  final _boundaryKey = GlobalKey();
  PosterPalette _palette = posterPalettes.first;
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await shareBoundaryAsImage(
        _boundaryKey,
        fileName: 'tabi-poster.png',
        text: 'Everywhere I explored on foot, with Tabi',
        pixelRatio: posterPixelRatio,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t create the poster. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(displayNameProvider) ?? 'Explorer';

    return Scaffold(
      appBar: AppBar(title: const Text('Your poster')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final palette in posterPalettes)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: palette.route),
                  label: Text(palette.name),
                  selected: palette == _palette,
                  onSelected: (_) => setState(() => _palette = palette),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: Poster(
                footprint: widget.footprint,
                palette: _palette,
                name: name,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AppButton(
            label: 'Share poster',
            icon: Icons.ios_share_rounded,
            loading: _sharing,
            expand: true,
            onPressed: _share,
          ),
        ),
      ),
    );
  }
}

/// The poster itself, 4:5 (an Instagram post): routes as line art, then the
/// explorer's name and totals.
class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.footprint,
    required this.palette,
    required this.name,
    this.width = 360,
  });

  final ExplorationFootprint footprint;
  final PosterPalette palette;
  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    TextStyle style(double size, FontWeight weight, {double spacing = 0}) =>
        TextStyle(
          color: palette.text,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
        );

    return SizedBox(
      width: width,
      height: width * 5 / 4,
      child: ColoredBox(
        color: palette.background,
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _RoutesPainter(footprint.routes, palette.route),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: style(22, FontWeight.w900, spacing: 2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'EXPLORED ON FOOT',
                    style: style(10, FontWeight.w700, spacing: 3),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _stat(
                        footprint.trekKm.toStringAsFixed(1),
                        'KM WALKED',
                        style,
                      ),
                      _stat('${footprint.trips}', 'TRIPS', style),
                      _stat('${footprint.cities}', 'CITIES', style),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'TABI',
                    style: style(
                      10,
                      FontWeight.w900,
                      spacing: 4,
                    ).copyWith(color: palette.route),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(
    String value,
    String label,
    TextStyle Function(double, FontWeight, {double spacing}) style,
  ) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: style(20, FontWeight.w800)),
        Text(label, style: style(9, FontWeight.w700, spacing: 1.5)),
      ],
    ),
  );
}

class _RoutesPainter extends CustomPainter {
  _RoutesPainter(this.routes, this.color);

  final List<List<LatLng>> routes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = projectRoutes(routes, size, padding: 28);
    final glow = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final route in projected) {
      if (route.length < 2) continue;
      final path = Path()..moveTo(route.first.dx, route.first.dy);
      for (final point in route.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_RoutesPainter old) =>
      old.color != color || !identical(old.routes, routes);
}
