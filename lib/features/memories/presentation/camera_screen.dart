import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:uuid/uuid.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/media_shell.dart';
import '../../../core/ui/friendly_error.dart';
import '../data/memory_repository.dart';
import '../domain/memory_model.dart';
import 'capture_button.dart';
import 'media_review.dart';

/// Holding the button records up to this long (you can't hold for long).
const maxHeldVideoLength = Duration(seconds: 60);

/// Video mode (tap to start, tap to stop, with pause) records up to this.
const maxVideoLength = Duration(minutes: 10);

/// Slow-motion clips are high frame rate, so big: up to this.
const maxSlowMotionLength = Duration(seconds: 60);

/// Video quality: about 30 MB a minute for normal video, more for
/// slow motion (more frames each second).
const videoBitrate = 4000000;
const slowMotionBitrate = 8000000;

/// The camera's time, replaceable in tests (recording lengths).
@visibleForTesting
DateTime Function() cameraClock = DateTime.now;

/// Photo; video (tap to start and stop, can pause); or slow motion. Holding
/// the button records a video in any mode.
enum CaptureMode { photo, video, slowMotion }

/// How fast a slow-motion clip plays back for the frame rate it was filmed
/// at: a quarter at 120 fps or more, a half at 60.
double slowMotionSpeed(int fps) => fps >= 120 ? 0.25 : 0.5;

/// The app's camera: photos and videos, no filters.
///
/// - Tap the button for a photo. Press and hold to record a video while
///   held (slide up to zoom). In Video mode, tap to start and tap to stop.
/// - Pinch to zoom, or tap 1× / 2×. Tap the picture to focus there;
///   double-tap to flip between the back and front cameras.
/// - Flash (off / auto / on; the torch while filming; a white screen as
///   the flash on the front camera), a 3 or 10 second timer, and a grid.
///
/// Returns the saved [Memory] (photo or video), or null.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, this.adventureId, this.proofMode = false});

  final String? adventureId;

  /// Proof-of-presence photo for a place: the live camera only, photos only.
  /// The gallery is hidden, because a photo picked from the gallery could
  /// have been taken anywhere, any time.
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

  /// Video needs the microphone; without it the camera still takes photos.
  late bool _audio = !widget.proofMode;
  bool _micBlocked = false;
  bool get _videoAvailable => !widget.proofMode && _audio;

  CaptureMode _mode = CaptureMode.photo;

  // Video.
  bool _recording = false;
  bool _heldRecording = false;
  bool _paused = false;
  Duration _elapsed = Duration.zero;
  Timer? _recordTicker;
  DateTime? _recordStartedAt;

  /// Recorded time before the current stretch (pauses don't count).
  Duration _recordedBefore = Duration.zero;
  DateTime? _stretchStartedAt;

  /// The frame rate the camera was opened at for slow motion (120, or 60
  /// when 120 isn't possible); null when not in slow motion.
  int? _slowFps;
  Future<LatLng?>? _recordWhere;

  // Zoom.
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _pinchStartZoom = 1;
  double? _dragStartY;
  double _dragStartZoom = 1;

  // Focus ring.
  Offset? _focusAt;
  int _focusTap = 0;

  // Flash, timer, grid.
  FlashMode _flash = FlashMode.off;
  int _timerSeconds = 0;
  int? _countdown;
  bool _flashing = false;
  bool _assistMode = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _controller?.dispose();
    super.dispose();
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
      if (mounted) {
        setState(
          () => _error = 'Could not start the camera. ${friendlyError(e)}',
        );
      }
    }
  }

  bool get _slowMode => _mode == CaptureMode.slowMotion;

  /// Slow motion: no sound (slowed sound is just noise) and a high frame
  /// rate, [fps].
  CameraController _makeController({int? fps}) => CameraController(
    _cameras[_cameraIndex],
    ResolutionPreset.high,
    enableAudio: _audio && fps == null,
    fps: fps,
    videoBitrate: fps == null ? videoBitrate : slowMotionBitrate,
  );

  /// Opens the camera at [_cameraIndex].
  void _startController() {
    final controller = _makeController(fps: _slowMode ? 120 : null);
    _controller = controller;
    _slowFps = _slowMode ? 120 : null;
    _initializeFuture = _initialize(controller);
    if (mounted) setState(() {});
  }

  Future<void> _initialize(CameraController controller) async {
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      // This phone can't film that fast: try 60 fps, then give up on
      // slow motion and go back to normal video.
      if (_slowFps != null) {
        await controller.dispose();
        for (final fps in [if (_slowFps! > 60) 60, null]) {
          final retry = _makeController(fps: fps);
          _controller = retry;
          try {
            await retry.initialize();
            _slowFps = fps;
            break;
          } on CameraException {
            await retry.dispose();
            if (fps == null) rethrow;
          }
        }
        if (_slowFps == null) {
          _mode = CaptureMode.video;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Slow motion isn\'t available on this phone.'),
              ),
            );
          }
        }
        return _afterInit();
      }
      // Microphone refused: keep the camera, photos only.
      if (!_audio || !e.code.toLowerCase().contains('audio')) rethrow;
      await controller.dispose();
      _audio = false;
      _micBlocked = true;
      final retry = _makeController();
      _controller = retry;
      await retry.initialize();
    }
    return _afterInit();
  }

  Future<void> _afterInit() async {
    final active = _controller!;
    try {
      _minZoom = await active.getMinZoomLevel();
      _maxZoom = await active.getMaxZoomLevel();
    } catch (_) {
      _minZoom = _maxZoom = 1;
    }
    _zoom = 1.0.clamp(_minZoom, _maxZoom);
    try {
      await active.setFlashMode(_flash);
    } catch (_) {
      // No flash on this camera.
    }
    if (mounted) setState(() {});
  }

  /// Switches between the back and front camera.
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switching || _isSaving || _recording) return;
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

  Future<void> _setMode(CaptureMode mode) async {
    if (mode == _mode || _recording || _isSaving) return;
    final reopen = (mode == CaptureMode.slowMotion) != _slowMode;
    setState(() => _mode = mode);
    if (!reopen) return;
    final old = _controller;
    setState(() {
      _controller = null;
      _initializeFuture = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await old?.dispose();
    if (mounted) _startController();
  }

  bool get _onBackCamera =>
      _cameras.isNotEmpty &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;

  // ---------------------------------------------------------------------------
  // Zoom and focus
  // ---------------------------------------------------------------------------

  Future<void> _setZoom(double zoom) async {
    final z = zoom.clamp(_minZoom, _maxZoom);
    if ((z - _zoom).abs() < 0.01) return;
    setState(() => _zoom = z);
    try {
      await _controller?.setZoomLevel(z);
    } catch (_) {
      // Zoom not supported: keep the number honest.
      if (mounted) setState(() => _zoom = 1.0.clamp(_minZoom, _maxZoom));
    }
  }

  void _focus(TapUpDetails details, Size box) {
    final c = _controller;
    if (c == null || _recording) return;
    final point = Offset(
      (details.localPosition.dx / box.width).clamp(0, 1),
      (details.localPosition.dy / box.height).clamp(0, 1),
    );
    setState(() {
      _focusAt = details.localPosition;
      _focusTap++;
    });
    final tap = _focusTap;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && tap == _focusTap) setState(() => _focusAt = null);
    });
    if (c.value.focusPointSupported) {
      c.setFocusPoint(point).catchError((Object _) {});
    }
    if (c.value.exposurePointSupported) {
      c.setExposurePoint(point).catchError((Object _) {});
    }
  }

  // ---------------------------------------------------------------------------
  // Flash and timer
  // ---------------------------------------------------------------------------

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() => _flash = next);
    if (_onBackCamera) {
      try {
        await _controller?.setFlashMode(next);
      } catch (_) {
        // No flash on this camera.
      }
    }
  }

  String get _flashLabel => switch (_flash) {
    FlashMode.auto => 'Flash: auto',
    FlashMode.always => 'Flash: on',
    _ => 'Flash: off',
  };

  void _cycleTimer() => setState(
    () => _timerSeconds = switch (_timerSeconds) {
      0 => 3,
      3 => 10,
      _ => 0,
    },
  );

  /// Counts down the self-timer. Returns false if it was cancelled (a tap
  /// on the button during the countdown).
  Future<bool> _runTimer() async {
    if (_timerSeconds == 0) return true;
    for (var s = _timerSeconds; s > 0; s--) {
      if (!mounted) return false;
      setState(() => _countdown = s);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_countdown == null) return false; // cancelled
    }
    if (mounted) setState(() => _countdown = null);
    return mounted;
  }

  /// A brief white flash over the preview when the shutter fires. On the
  /// front camera with the flash on, a longer, full white screen lights the
  /// face instead of a flash.
  Future<void> _flashScreen({required bool frontLight}) async {
    if (MediaQuery.disableAnimationsOf(context) && !frontLight) return;
    setState(() => _flashing = true);
    await Future<void>.delayed(Duration(milliseconds: frontLight ? 350 : 90));
    if (!frontLight && mounted) setState(() => _flashing = false);
  }

  // ---------------------------------------------------------------------------
  // Photo
  // ---------------------------------------------------------------------------

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSaving) {
      return;
    }
    if (_countdown != null) {
      setState(() => _countdown = null); // tap again cancels the timer
      return;
    }
    if (!await _runTimer()) return;

    setState(() => _isSaving = true);
    try {
      HapticFeedback.mediumImpact();
      final frontLight = !_onBackCamera && _flash != FlashMode.off;
      await _flashScreen(frontLight: frontLight);
      final file = await controller.takePicture();
      if (frontLight && mounted) setState(() => _flashing = false);
      // Time and place are those of the shutter, not of the moment the photo
      // is accepted: a place's proof photo must show where you were when you
      // took it.
      final capturedAt = DateTime.now();
      final location = ref.read(locationServiceProvider).getCurrentLocation();

      if (!mounted) return;
      final outcome = await Navigator.of(context).push<ReviewOutcome>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaReviewScreen(files: [file.path], isVideo: false),
        ),
      );
      // Retake, close and back all mean "try again".
      if (outcome?.choice != ReviewChoice.use) {
        // Retake: forget this photo and stay on the camera.
        try {
          await File(file.path).delete();
        } catch (_) {}
        return;
      }
      await _saveMemory(
        file,
        type: MemoryType.photo,
        capturedAt: capturedAt,
        location: await location,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _flashing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save photo. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Video
  // ---------------------------------------------------------------------------

  Future<void> _startVideo({required bool held}) async {
    final controller = _controller;
    if (!_videoAvailable ||
        controller == null ||
        !controller.value.isInitialized ||
        _recording ||
        _isSaving) {
      return;
    }
    if (!held && !await _runTimer()) return;
    try {
      if (_flash != FlashMode.off && _onBackCamera) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
      await controller.startVideoRecording();
      HapticFeedback.mediumImpact();
      _recordStartedAt = cameraClock();
      _recordedBefore = Duration.zero;
      _stretchStartedAt = _recordStartedAt;
      _recordWhere = ref
          .read(locationServiceProvider)
          .getCurrentLocation(acceptRecent: true);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _heldRecording = held;
        _paused = false;
        _elapsed = Duration.zero;
      });
      _recordTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || _paused) return;
        setState(() => _elapsed = _recordedNow());
        if (_elapsed >= _maxLength) _stopVideo();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t start recording. ${friendlyError(e)}'),
        ),
      );
    }
  }

  /// Recorded time so far, not counting pauses.
  Duration _recordedNow() {
    final stretch = _stretchStartedAt;
    if (_paused || stretch == null) return _recordedBefore;
    return _recordedBefore + cameraClock().difference(stretch);
  }

  /// The longest this recording can be.
  Duration get _maxLength {
    if (_heldRecording) return maxHeldVideoLength;
    return _slowMode ? maxSlowMotionLength : maxVideoLength;
  }

  Future<void> _togglePause() async {
    final controller = _controller;
    if (!_recording || controller == null) return;
    try {
      if (_paused) {
        await controller.resumeVideoRecording();
        _stretchStartedAt = cameraClock();
        setState(() => _paused = false);
      } else {
        await controller.pauseVideoRecording();
        _recordedBefore = _recordedNow();
        setState(() {
          _paused = true;
          _elapsed = _recordedBefore;
        });
      }
      HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t pause on this phone. ${friendlyError(e)}'),
        ),
      );
    }
  }

  Future<void> _stopVideo() async {
    final controller = _controller;
    if (!_recording || controller == null) return;
    _recordTicker?.cancel();
    final length = _recordedNow();
    final speed = _slowFps == null ? 1.0 : slowMotionSpeed(_slowFps!);
    setState(() {
      _recording = false;
      _heldRecording = false;
      _paused = false;
      _isSaving = true;
    });
    XFile? file;
    try {
      file = await controller.stopVideoRecording();
      HapticFeedback.lightImpact();
      try {
        await controller.setFlashMode(_onBackCamera ? _flash : FlashMode.off);
      } catch (_) {}
      if (!mounted) return;
      final outcome = await Navigator.of(context).push<ReviewOutcome>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaReviewScreen(
            files: [file!.path],
            isVideo: true,
            retakeLabel: 'Record again',
            playbackSpeed: speed,
          ),
        ),
      );
      if (outcome?.choice != ReviewChoice.use) {
        try {
          await File(file.path).delete();
        } catch (_) {}
        return;
      }
      await _saveMemory(
        file,
        type: MemoryType.video,
        capturedAt: _recordStartedAt ?? DateTime.now(),
        location: await _recordWhere,
        // How long it plays: a slowed clip plays longer than it took.
        durationSeconds: (length.inMilliseconds / 1000 / speed).ceil().clamp(
          1,
          1 << 20,
        ),
        playbackSpeed: speed < 1 ? speed : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save video. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Hold to record: slide up to zoom in, down to zoom out.
  void _holdMoved(LongPressMoveUpdateDetails d) {
    final start = _dragStartY;
    if (start == null || _maxZoom <= _minZoom) return;
    final dy = start - d.globalPosition.dy; // up is positive
    _setZoom(_dragStartZoom + dy / 250 * (_maxZoom - _minZoom) / 4);
  }

  // ---------------------------------------------------------------------------
  // Gallery and saving
  // ---------------------------------------------------------------------------

  Future<void> _pickFromGallery() async {
    if (_isSaving || _recording) return;
    setState(() => _isSaving = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _saveMemory(
        file,
        type: MemoryType.photo,
        capturedAt: DateTime.now(),
        location: await ref.read(locationServiceProvider).getCurrentLocation(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not use that photo. ${friendlyError(e)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveMemory(
    XFile file, {
    required MemoryType type,
    required DateTime capturedAt,
    required LatLng? location,
    int? durationSeconds,
    double? playbackSpeed,
  }) async {
    final savedPath = await _persistFile(file);

    final memory = Memory(
      id: const Uuid().v4(),
      type: type,
      filePath: savedPath,
      timestamp: capturedAt,
      adventureId: widget.adventureId,
      latitude: location?.latitude,
      longitude: location?.longitude,
      durationSeconds: durationSeconds,
      playbackSpeed: playbackSpeed,
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Why proof mode wants a live photo, one tap away.
  void _explainProof() {
    showAppSheet<void>(
      context,
      title: 'Why a live photo?',
      body: Text(
        'This photo shows you reached the place. It has to come from the '
        'camera now, so the gallery is off, and the time and your location '
        'are saved with it when you press the shutter.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  /// A black screen with a close button and a message (loading, errors).
  Widget _message({required Widget child}) => MediaShell(
    body: Center(
      child: Padding(padding: const EdgeInsets.all(32), child: child),
    ),
  );

  Widget _blocked(String message) => _message(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.no_photography_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: mediaOnColor),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: openAppSettings,
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  String get _hint {
    if (_recording) {
      if (_heldRecording) return 'Release to stop';
      return _paused ? 'Paused · tap to stop' : 'Tap to stop';
    }
    if (_slowMode) {
      return _slowFps == null
          ? 'Tap to start'
          : 'Tap to start · ${_slowFps! >= 120 ? '¼' : '½'} speed, no sound';
    }
    if (_mode == CaptureMode.video) return 'Tap to start recording';
    return _videoAvailable ? 'Tap for photo · hold for video' : 'Tap for photo';
  }

  String get _buttonLabel {
    if (_recording) return 'Stop recording';
    if (_slowMode) return 'Start slow-motion recording';
    if (_mode == CaptureMode.video) return 'Start recording';
    return widget.proofMode ? 'Take verification photo' : 'Take photo';
  }

  void _onButtonTap() {
    if (_recording) {
      _stopVideo();
    } else if (_mode != CaptureMode.photo) {
      _startVideo(held: false);
    } else {
      _takePhoto();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _blocked(_error!);

    final controller = _controller;
    if (controller == null || _initializeFuture == null) {
      return _message(child: const CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _blocked(
            'Couldn\'t open the camera. Allow camera access for this app '
            'in your phone settings, then try again.',
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _message(child: const CircularProgressIndicator());
        }
        final active = _controller ?? controller;
        return PopScope(
          // Leaving while recording would lose the clip: stop it first.
          canPop: !_recording,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _stopVideo();
          },
          child: MediaShell(
            chromeVisible: !_recording,
            actions: [
              IconButton(
                icon: Icon(switch (_flash) {
                  FlashMode.auto => Icons.flash_auto_rounded,
                  FlashMode.always => Icons.flash_on_rounded,
                  _ => Icons.flash_off_rounded,
                }),
                tooltip: _flashLabel,
                onPressed: _cycleFlash,
              ),
              IconButton(
                icon: Icon(
                  _timerSeconds == 0
                      ? Icons.timer_off_outlined
                      : (_timerSeconds == 3
                            ? Icons.timer_3_rounded
                            : Icons.timer_10_rounded),
                ),
                tooltip: _timerSeconds == 0
                    ? 'Timer: off'
                    : 'Timer: $_timerSeconds seconds',
                onPressed: _cycleTimer,
              ),
              IconButton(
                icon: Icon(
                  _assistMode ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                ),
                tooltip: _assistMode ? 'Grid: on' : 'Grid: off',
                onPressed: () => setState(() => _assistMode = !_assistMode),
              ),
            ],
            body: LayoutBuilder(
              builder: (context, box) => Stack(
                fit: StackFit.expand,
                children: [
                  // Full-bleed preview: tap to focus, double-tap to flip,
                  // pinch to zoom.
                  Positioned.fill(
                    child: Semantics(
                      label:
                          'Camera view. Tap to focus'
                          '${_cameras.length > 1 ? ', double-tap to flip the camera' : ''}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _focus(d, box.biggest),
                        onDoubleTap: _switchCamera,
                        onScaleStart: (_) => _pinchStartZoom = _zoom,
                        onScaleUpdate: (d) {
                          if (d.pointerCount >= 2) {
                            _setZoom(_pinchStartZoom * d.scale);
                          }
                        },
                        child: ValueListenableBuilder<CameraValue>(
                          valueListenable: active,
                          builder: (context, value, _) => CoverPreview(
                            aspectRatio: previewBoxRatio(value),
                            child: CameraPreview(active),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_assistMode)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _RuleOfThirdsPainter()),
                      ),
                    ),
                  if (_focusAt case final at?)
                    Positioned(
                      left: at.dx - 36,
                      top: at.dy - 36,
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(_focusTap),
                          tween: Tween(begin: 1.4, end: 1),
                          duration: AppMotion.base,
                          builder: (_, scale, _) => Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.amber,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_recording)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _RecordingPill(
                          elapsed: _elapsed,
                          max: _maxLength,
                          paused: _paused,
                          slowMotion: _slowMode,
                        ),
                      ),
                    ),
                  if (widget.proofMode)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 64,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Material(
                          color: mediaScrim,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: _explainProof,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Verification photo · location on',
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.info_outline_rounded, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_countdown case final n?)
                    Center(
                      child: IgnorePointer(
                        child: Semantics(
                          liveRegion: true,
                          label: '$n',
                          child: Text(
                            '$n',
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(color: mediaOnColor),
                          ),
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _flashing ? 0.9 : 0,
                      duration: const Duration(milliseconds: 80),
                      child: const ColoredBox(color: mediaOnColor),
                    ),
                  ),
                  if (kDebugMode)
                    Positioned(
                      bottom: 200,
                      left: 8,
                      child: IgnorePointer(
                        child: ValueListenableBuilder<CameraValue>(
                          valueListenable: active,
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
                  // The bottom controls stay visible while recording (the
                  // button is the way to stop), so they live here rather
                  // than in the shell's bar that hides.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _BottomControls(
                      hint: _hint,
                      recording: _recording,
                      zoom: _zoom,
                      maxZoom: _maxZoom,
                      onZoom: _setZoom,
                      showModes: _videoAvailable && !_recording,
                      mode: _mode,
                      onMode: _setMode,
                      micBlocked: _micBlocked && !widget.proofMode,
                      // While recording (not held): Pause / Resume here.
                      gallery: _recording && !_heldRecording
                          ? IconButton(
                              iconSize: 28,
                              tooltip: _paused ? 'Resume' : 'Pause',
                              onPressed: _togglePause,
                              icon: Icon(
                                _paused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                            )
                          : widget.proofMode || _recording
                          ? null
                          : IconButton(
                              iconSize: 28,
                              icon: const Icon(Icons.photo_library_outlined),
                              tooltip: 'Choose from gallery',
                              onPressed: _isSaving ? null : _pickFromGallery,
                            ),
                      flip: _cameras.length > 1 && !_recording
                          ? IconButton(
                              iconSize: 28,
                              tooltip: _onBackCamera
                                  ? 'Use the front camera'
                                  : 'Use the back camera',
                              onPressed: _isSaving || _switching
                                  ? null
                                  : _switchCamera,
                              icon: const Icon(Icons.cameraswitch_rounded),
                            )
                          : null,
                      button: CaptureButton(
                        key: const Key('shutter'),
                        recording: _recording,
                        progress:
                            _elapsed.inMilliseconds / _maxLength.inMilliseconds,
                        busy: _isSaving,
                        semanticLabel: _buttonLabel,
                        onTap: _isSaving ? null : _onButtonTap,
                        onLongPressStart: _videoAvailable && !_recording
                            ? (d) {
                                _dragStartY = d.globalPosition.dy;
                                _dragStartZoom = _zoom;
                                _startVideo(held: true);
                              }
                            : null,
                        onLongPressMoveUpdate: _holdMoved,
                        onLongPressEnd: (_) {
                          _dragStartY = null;
                          if (_heldRecording) _stopVideo();
                        },
                        onSemanticLongPress: _videoAvailable
                            ? () => _recording
                                  ? _stopVideo()
                                  : _startVideo(held: false)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Red dot and the clip length while recording: "0:12 / 1:00".
class _RecordingPill extends StatelessWidget {
  const _RecordingPill({
    required this.elapsed,
    required this.max,
    required this.paused,
    required this.slowMotion,
  });

  final Duration elapsed;
  final Duration max;
  final bool paused;
  final bool slowMotion;

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final what = paused
        ? 'Paused'
        : (slowMotion ? 'Recording slow motion' : 'Recording');
    return Semantics(
      label: '$what, ${_clock(elapsed)} of ${_clock(max)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: const ShapeDecoration(
          color: mediaScrim,
          shape: StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paused ? Icons.pause_rounded : Icons.circle,
              size: paused ? 16 : 10,
              color: paused ? mediaOnColor : recordRed,
            ),
            const SizedBox(width: 8),
            Text(
              [
                if (paused) 'Paused',
                if (slowMotion && !paused) 'Slow-mo',
                '${_clock(elapsed)} / ${_clock(max)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: mediaOnColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zoom chips, Photo / Video, the hint, and the gallery · button · flip row.
class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.hint,
    required this.recording,
    required this.zoom,
    required this.maxZoom,
    required this.onZoom,
    required this.showModes,
    required this.mode,
    required this.onMode,
    required this.micBlocked,
    required this.button,
    this.gallery,
    this.flip,
  });

  final String hint;
  final bool recording;
  final double zoom;
  final double maxZoom;
  final ValueChanged<double> onZoom;
  final bool showModes;
  final CaptureMode mode;
  final ValueChanged<CaptureMode> onMode;
  final bool micBlocked;
  final Widget button;
  final Widget? gallery;
  final Widget? flip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final zoomStops = [1.0, if (maxZoom >= 2) 2.0];
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [mediaScrim, mediaScrimClear],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (zoomStops.length > 1 || zoom > 1.05)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final stop in zoomStops)
                      _ZoomChip(
                        label: (zoom - stop).abs() < 0.05
                            ? '${zoom.toStringAsFixed(1)}×'
                            : '${stop.toStringAsFixed(0)}×',
                        selected: stop == 2.0 ? zoom >= 1.95 : zoom < 1.95,
                        onTap: () => onZoom(stop),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              if (showModes)
                // Wraps on small phones with large text instead of
                // overflowing.
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final m in CaptureMode.values)
                      TextButton(
                        onPressed: () => onMode(m),
                        style: TextButton.styleFrom(
                          foregroundColor: m == mode
                              ? AppTheme.amber
                              : mediaOnColorMuted,
                        ),
                        child: Text(
                          switch (m) {
                            CaptureMode.photo => 'PHOTO',
                            CaptureMode.video => 'VIDEO',
                            CaptureMode.slowMotion => 'SLOW-MO',
                          },
                          semanticsLabel:
                              '${switch (m) {
                                CaptureMode.photo => 'Photo',
                                CaptureMode.video => 'Video',
                                CaptureMode.slowMotion => 'Slow motion',
                              }} mode${m == mode ? ', selected' : ''}',
                        ),
                      ),
                  ],
                ),
              Row(
                children: [
                  Expanded(child: Center(heightFactor: 1, child: gallery)),
                  button,
                  Expanded(child: Center(heightFactor: 1, child: flip)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                style: text.labelMedium?.copyWith(color: mediaOnColorMuted),
              ),
              if (micBlocked)
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text('Allow the microphone to record video'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Zoom $label',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              color: mediaScrim,
              shape: const StadiumBorder(),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: selected ? AppTheme.amber : mediaOnColor),
            ),
          ),
        ),
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
