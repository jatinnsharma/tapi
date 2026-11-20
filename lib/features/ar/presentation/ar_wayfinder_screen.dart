import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../application/compass_service.dart';
import '../domain/ar_math.dart';

/// AR needs a back camera and a compass: phones only.
bool get arSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// The AR view closes itself after this long without a tap (camera, GPS
/// and sensors all use battery).
const arIdleTimeout = Duration(seconds: 90);

/// Opens the AR wayfinder towards [name] at [target].
Future<void> showArWayfinder(
  BuildContext context, {
  required String name,
  required LatLng target,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ArWayfinderScreen(name: name, target: target),
    ),
  );
}

/// The camera view with a pin over the direction of [target], its distance,
/// and an arrow to turn towards it: for narrow lanes where a map's "which
/// way" is hard to read.
class ArWayfinderScreen extends ConsumerStatefulWidget {
  const ArWayfinderScreen({
    super.key,
    required this.name,
    required this.target,
  });

  final String name;
  final LatLng target;

  @override
  ConsumerState<ArWayfinderScreen> createState() => _ArWayfinderScreenState();
}

class _ArWayfinderScreenState extends ConsumerState<ArWayfinderScreen> {
  CameraController? _camera;
  String? _cameraError;
  LatLng? _here;
  StreamSubscription<LatLng>? _location;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _startCamera();
    final service = ref.read(locationServiceProvider);
    service.getCurrentLocation(acceptRecent: true).then((p) {
      if (mounted && p != null) setState(() => _here = p);
    });
    _location = service.getLocationStream().listen((p) {
      if (mounted) setState(() => _here = p);
    });
    _resetIdle();
  }

  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(arIdleTimeout, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (_) {
      if (mounted) setState(() => _cameraError = 'Camera not available');
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _location?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compass = ref.watch(compassProvider).value;
    final here = _here;
    final heading = compass?.heading;
    final bearing = here == null ? null : bearingDegrees(here, widget.target);
    final meters = here == null
        ? null
        : const Distance()(here, widget.target).round();
    final delta = bearing == null || heading == null
        ? null
        : angleDelta(bearing, heading);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _resetIdle,
        child: LayoutBuilder(
          builder: (context, box) {
            final x = delta == null ? null : screenOffsetX(delta, box.maxWidth);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (_camera != null)
                  CameraPreview(_camera!)
                else
                  Center(
                    child: Text(
                      _cameraError ?? 'Starting camera…',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                if (x != null)
                  Positioned(
                    left: x - 60,
                    top: box.maxHeight * 0.3,
                    width: 120,
                    child: _Pin(name: widget.name, meters: meters),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: _Guide(
                    delta: delta,
                    meters: meters,
                    name: widget.name,
                    waitingForGps: here == null,
                    flat: compass != null && heading == null,
                  ),
                ),
                if (compass?.disturbed ?? false)
                  const Positioned(
                    left: 16,
                    right: 16,
                    top: 100,
                    child: _Hint(
                      'Compass disturbed: move away from metal or vehicles, '
                      'or wave your phone in a figure 8.',
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton.filled(
                      tooltip: 'Back to the map',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.name, required this.meters});

  final String name;
  final int? meters;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.forest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            meters == null ? name : '$name\n$meters m',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Icon(Icons.location_on, color: AppTheme.amber, size: 56),
      ],
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({
    required this.delta,
    required this.meters,
    required this.name,
    required this.waitingForGps,
    required this.flat,
  });

  final double? delta;
  final int? meters;
  final String name;
  final bool waitingForGps;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (waitingForGps) {
      text = 'Finding your location…';
    } else if (flat) {
      text = 'Hold your phone upright, camera facing ahead.';
    } else if (delta == null) {
      text = 'Starting the compass…';
    } else if (delta!.abs() <= 15) {
      text = '$name • ${meters ?? '?'} m ahead';
    } else {
      text =
          'Turn ${delta! > 0 ? 'right' : 'left'} ${delta!.abs().round()}° '
          '• ${meters ?? '?'} m';
    }

    return Column(
      children: [
        if (delta != null)
          Transform.rotate(
            angle: delta! * math.pi / 180,
            child: const Icon(
              Icons.navigation_rounded,
              color: AppTheme.amber,
              size: 64,
            ),
          ),
        const SizedBox(height: 8),
        _Hint(text),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
