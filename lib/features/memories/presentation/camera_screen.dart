import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/location_service.dart';

import 'package:latlong2/latlong.dart';

import '../data/memory_repository.dart';
import '../domain/memory_model.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, this.adventureId, this.proofMode = false});

  final String? adventureId;

  /// Proof-of-presence photo for a place: the live camera only. The gallery
  /// is hidden, because a photo picked from the gallery could have been
  /// taken anywhere, any time.
  final bool proofMode;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _error;
  bool _isSaving = false;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = sortCameras(await availableCameras());
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _error = 'No camera available on this device.');
        }
        return;
      }
      _cameras = cameras;
      _cameraIndex = 0; // the back camera, when there is one
      _startController();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  /// Opens the camera at [_cameraIndex].
  void _startController() {
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false, // photos only: no microphone permission needed
    );
    _controller = controller;
    _initializeFuture = controller.initialize();
    if (mounted) setState(() {});
  }

  /// Switches between the back and front camera.
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switching || _isSaving) return;
    setState(() => _switching = true);
    final old = _controller;
    // Take the old preview off screen first, then release the camera.
    setState(() {
      _controller = null;
      _initializeFuture = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await old?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    if (mounted) _startController();
    if (mounted) setState(() => _switching = false);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final file = await controller.takePicture();
      // Time and place are those of the shutter, not of the moment the photo
      // is accepted: a place's proof photo must show where you were when you
      // took it.
      final capturedAt = DateTime.now();
      final location = ref.read(locationServiceProvider).getCurrentLocation();

      if (!mounted) return;
      final keep = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PhotoReviewScreen(photo: File(file.path)),
        ),
      );
      if (keep != true) {
        // Retake: forget this photo and stay on the camera.
        try {
          await File(file.path).delete();
        } catch (_) {}
        return;
      }
      await _saveMemory(file, capturedAt: capturedAt, location: await location);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _saveMemory(
        file,
        capturedAt: DateTime.now(),
        location: await ref.read(locationServiceProvider).getCurrentLocation(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not use that photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveMemory(
    XFile file, {
    required DateTime capturedAt,
    required LatLng? location,
  }) async {
    final savedPath = await _persistFile(file);

    final memory = Memory(
      id: const Uuid().v4(),
      type: MemoryType.photo,
      filePath: savedPath,
      timestamp: capturedAt,
      adventureId: widget.adventureId,
      latitude: location?.latitude,
      longitude: location?.longitude,
    );
    await ref.read(memoryRepositoryProvider).saveMemory(memory);

    if (mounted) Navigator.of(context).pop(memory);
  }

  Future<String> _persistFile(XFile file) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final memoriesDir = Directory(p.join(docsDir.path, 'memories'));
    if (!await memoriesDir.exists()) {
      await memoriesDir.create(recursive: true);
    }
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final destination = p.join(memoriesDir.path, fileName);
    await File(file.path).copy(destination);
    return destination;
  }

  bool _assistMode = false;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera')),
        body: Center(child: Text(_error!)),
      );
    }

    final controller = _controller;
    if (controller == null || _initializeFuture == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Memory'),
        actions: [
          IconButton(
            icon: Icon(Icons.grid_on, color: _assistMode ? Colors.amber : null),
            tooltip: 'AI Photo Assistant',
            onPressed: () {
              setState(() {
                _assistMode = !_assistMode;
              });
            },
          ),
          if (!widget.proofMode)
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: 'Choose from gallery',
              onPressed: _isSaving ? null : _pickFromGallery,
            ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not open the camera. Check the camera permission '
                  'in your phone settings, then try again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          // StackFit.expand: without it the stack shrinks to its only
          // un-positioned child (the capture button) and the preview with it.
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<CameraValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => CoverPreview(
                    aspectRatio: previewBoxRatio(value),
                    child: CameraPreview(controller),
                  ),
                ),
              ),
              if (kDebugMode)
                Positioned(
                  top: 4,
                  left: 8,
                  child: IgnorePointer(
                    child: ValueListenableBuilder<CameraValue>(
                      valueListenable: controller,
                      builder: (context, v, _) => Text(
                        'camera ${v.previewSize?.width.round()}x'
                        '${v.previewSize?.height.round()}  '
                        '${v.deviceOrientation.name}  '
                        'box ${previewBoxRatio(v).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          backgroundColor: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_assistMode)
                Positioned.fill(
                  child: CustomPaint(painter: _RuleOfThirdsPainter()),
                ),
              if (_assistMode)
                Positioned(
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.amber, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Place subject on the grid intersections',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_cameras.length > 1)
                Positioned(
                  right: 32,
                  bottom: 52,
                  child: FloatingActionButton(
                    heroTag: 'switch-camera',
                    tooltip:
                        _cameras[_cameraIndex].lensDirection ==
                            CameraLensDirection.back
                        ? 'Use the front camera'
                        : 'Use the back camera',
                    onPressed: _isSaving || _switching ? null : _switchCamera,
                    child: const Icon(Icons.cameraswitch_rounded),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: FloatingActionButton.large(
                    heroTag: 'shutter',
                    onPressed: _isSaving ? null : _capture,
                    child: _isSaving
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.camera_alt),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shows a photo just taken, full screen, to keep or retake. Pops `true` to
/// keep it and `false` (also on back) to retake.
class PhotoReviewScreen extends StatelessWidget {
  const PhotoReviewScreen({super.key, required this.photo});

  final File photo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Review photo'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Retake',
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.file(
                  photo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text(
                    'Could not show this photo.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retake'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Use photo'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Width / height of the box the camera plugin's own CameraPreview draws:
/// the sensor's (landscape) ratio when the phone is held sideways, the
/// other way round when upright. This is the plugin's rule, read from the
/// camera's own state so the two always agree.
double previewBoxRatio(CameraValue value) {
  final orientation =
      value.previewPauseOrientation ??
      value.lockedCaptureOrientation ??
      value.deviceOrientation;
  final landscape =
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
  final sensor = value.previewSize == null ? 0.0 : value.aspectRatio;
  if (!sensor.isFinite || sensor <= 0) return 3 / 4;
  return landscape ? sensor : 1 / sensor;
}

/// The phone's cameras with the back one first, then the front, then any
/// others (external or unknown). Only one of each kind is kept for flipping,
/// so phones that list several back lenses still flip back <-> front.
List<CameraDescription> sortCameras(List<CameraDescription> all) {
  CameraDescription? first(CameraLensDirection d) {
    for (final c in all) {
      if (c.lensDirection == d) return c;
    }
    return null;
  }

  final ordered = [
    first(CameraLensDirection.back),
    first(CameraLensDirection.front),
    first(CameraLensDirection.external),
  ].whereType<CameraDescription>().toList();
  return ordered;
}

/// Fills all the space it is given with [child] (a camera preview of shape
/// [aspectRatio]), cropping the overflow instead of leaving bars or squeezing.
class CoverPreview extends StatelessWidget {
  const CoverPreview({
    super.key,
    required this.aspectRatio,
    required this.child,
  });

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: 1000 * aspectRatio, height: 1000, child: child),
      ),
    );
  }
}

class _RuleOfThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;

    final cellWidth = size.width / 3;
    final cellHeight = size.height / 3;

    // Vertical lines
    canvas.drawLine(
      Offset(cellWidth, 0),
      Offset(cellWidth, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(cellWidth * 2, 0),
      Offset(cellWidth * 2, size.height),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(0, cellHeight),
      Offset(size.width, cellHeight),
      paint,
    );
    canvas.drawLine(
      Offset(0, cellHeight * 2),
      Offset(size.width, cellHeight * 2),
      paint,
    );

    // Intersections (points of interest)
    final points = [
      Offset(cellWidth, cellHeight),
      Offset(cellWidth * 2, cellHeight),
      Offset(cellWidth, cellHeight * 2),
      Offset(cellWidth * 2, cellHeight * 2),
    ];

    final dotPaint = Paint()..color = Colors.amber.withValues(alpha: 0.8);
    for (final point in points) {
      canvas.drawCircle(point, 6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
