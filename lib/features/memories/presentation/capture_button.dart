import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/media_shell.dart';

/// Recording red on the dark camera (the ring, dot and timer).
const Color recordRed = mediaRecordRed;

/// The camera's main button. Tap: photo (or start/stop in Video mode).
/// Press and hold: record a video while held; slide up while holding to
/// zoom. While recording it grows, turns red and fills a ring as the
/// clip nears its maximum length.
class CaptureButton extends StatelessWidget {
  const CaptureButton({
    super.key,
    required this.recording,
    required this.progress,
    required this.semanticLabel,
    this.busy = false,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onSemanticLongPress,
  });

  final bool recording;

  /// How much of the maximum clip length is used (0–1).
  final double progress;
  final bool busy;
  final String semanticLabel;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  /// What a screen reader's long-press does (start or stop a video), since
  /// holding a button isn't possible there.
  final VoidCallback? onSemanticLongPress;

  static const double idleSize = 80;
  static const double recordingSize = 104;

  @override
  Widget build(BuildContext context) {
    final size = recording ? recordingSize : idleSize;
    final animate = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.base;
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? '$semanticLabel, saving' : semanticLabel,
      onTap: busy ? null : onTap,
      onLongPress: busy ? null : onSemanticLongPress,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        onLongPressStart: busy ? null : onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        // A fixed box so the layout doesn't jump while it grows.
        child: SizedBox.square(
          dimension: recordingSize,
          child: Center(
            child: AnimatedContainer(
              duration: animate,
              curve: AppMotion.curve,
              width: size,
              height: size,
              child: CustomPaint(
                painter: _RingPainter(
                  recording: recording,
                  progress: progress.clamp(0.0, 1.0),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: animate,
                    width: recording ? 36 : 62,
                    height: recording ? 36 : 62,
                    decoration: BoxDecoration(
                      color: recording ? recordRed : mediaOnColor,
                      borderRadius: BorderRadius.circular(recording ? 10 : 31),
                    ),
                    alignment: Alignment.center,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: mediaOnLight,
                            ),
                          )
                        : null,
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

class _RingPainter extends CustomPainter {
  _RingPainter({required this.recording, required this.progress});

  final bool recording;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    canvas.drawArc(
      ring,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = recording ? mediaRingDim : mediaOnColor,
    );
    if (recording && progress > 0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = recordRed,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.recording != recording || old.progress != progress;
}
