import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/friendly_error.dart';
import '../data/memory_repository.dart';
import '../domain/memory_model.dart';

/// Shows the voice note recorder as a bottom sheet. Resolves to the saved
/// [Memory] if the user records and saves a note, or `null` if dismissed.
Future<Memory?> showVoiceRecorderSheet(
  BuildContext context, {
  String? adventureId,
}) {
  return showModalBottomSheet<Memory>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => VoiceRecorderWidget(adventureId: adventureId),
  );
}

class VoiceRecorderWidget extends ConsumerStatefulWidget {
  const VoiceRecorderWidget({super.key, this.adventureId});

  final String? adventureId;

  @override
  ConsumerState<VoiceRecorderWidget> createState() =>
      _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends ConsumerState<VoiceRecorderWidget> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  Timer? _ticker;

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isSaving = false;

  /// Shown in the sheet itself (a snackbar would hide behind it).
  String? _error;
  bool _needsPermission = false;

  /// Voice notes stop on their own at this length.
  static const maxLength = Duration(minutes: 3);
  String? _recordedPath;
  Duration _elapsed = Duration.zero;

  /// When and where the note was recorded (set when recording stops), so a
  /// long listen-back doesn't change them.
  DateTime? _recordedAt;
  Future<LatLng?>? _recordedWhere;

  /// Set once the note is saved; otherwise the file is deleted on the way out.
  bool _kept = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    _player.dispose();
    final path = _recordedPath;
    if (!_kept && path != null) {
      // Swiped away without saving: don't leave the recording behind.
      File(path).delete().then((_) {}, onError: (_) {});
    }
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      _error = null;
      _needsPermission = false;
    });
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) setState(() => _needsPermission = true);
        return;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final memoriesDir = Directory(p.join(docsDir.path, 'memories'));
      if (!await memoriesDir.exists()) {
        await memoriesDir.create(recursive: true);
      }
      final path = p.join(memoriesDir.path, '${const Uuid().v4()}.m4a');

      await _recorder.start(const RecordConfig(), path: path);

      _elapsed = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed >= maxLength) _stopRecording();
      });

      setState(() {
        _isRecording = true;
        _recordedPath = path;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Couldn\'t start recording. ${friendlyError(e)}',
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    try {
      final path = await _recorder.stop();
      _recordedAt = DateTime.now();
      _recordedWhere = ref
          .read(locationServiceProvider)
          .getCurrentLocation(acceptRecent: true);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordedPath = path ?? _recordedPath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _error = 'Couldn\'t finish the recording. ${friendlyError(e)}';
      });
    }
  }

  Future<void> _togglePlayback() async {
    final path = _recordedPath;
    if (path == null) return;
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }
    await _player.play(DeviceFileSource(path));
    setState(() => _isPlaying = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  Future<void> _deleteRecording() async {
    final path = _recordedPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _recordedPath = null;
  }

  /// Throws the recording away and goes back to record another.
  Future<void> _recordAgain() async {
    await _player.stop();
    await _deleteRecording();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _save() async {
    final path = _recordedPath;
    if (path == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final location = await _recordedWhere;
      final memory = Memory(
        id: const Uuid().v4(),
        type: MemoryType.voiceNote,
        filePath: path,
        timestamp: _recordedAt ?? DateTime.now(),
        adventureId: widget.adventureId,
        latitude: location?.latitude,
        longitude: location?.longitude,
        durationSeconds: _elapsed.inSeconds,
      );
      await ref.read(memoryRepositoryProvider).saveMemory(memory);
      _kept = true;
      if (mounted) Navigator.of(context).pop(memory);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t save it. ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _recordedPath != null && !_isRecording;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isRecording
                ? 'Recording…'
                : (hasRecording ? 'Your voice note' : 'Voice note'),
            textAlign: TextAlign.center,
            style: text.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isRecording) ...[
                _PulsingDot(color: colors.danger),
                const SizedBox(width: 10),
              ],
              Semantics(
                liveRegion: _isRecording,
                child: Text(
                  _formatDuration(_elapsed),
                  style: text.displaySmall?.copyWith(
                    color: _isRecording ? colors.danger : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          Text(
            _isRecording
                ? 'Stops by itself at ${_formatDuration(maxLength)}'
                : hasRecording
                ? 'Listen back, then save it.'
                : 'Up to ${_formatDuration(maxLength)}',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (_needsPermission) ...[
            const SizedBox(height: 16),
            StatusBanner(
              kind: StatusKind.warning,
              title: 'Microphone is off',
              message: 'Allow the microphone for this app to record.',
              actionLabel: 'Open settings',
              onAction: openAppSettings,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            StatusBanner(
              kind: StatusKind.error,
              title: 'Something went wrong',
              message: _error,
            ),
          ],
          const SizedBox(height: 24),
          if (!hasRecording)
            Center(
              child: Semantics(
                button: true,
                label: _isRecording ? 'Stop recording' : 'Start recording',
                excludeSemantics: true,
                child: SizedBox.square(
                  dimension: 76,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: _isRecording ? colors.danger : null,
                    ),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 36,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Center(
              child: IconButton.filledTonal(
                iconSize: 32,
                tooltip: _isPlaying ? 'Stop' : 'Play it back',
                onPressed: _togglePlayback,
                icon: Icon(
                  _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton.tertiary(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    onPressed: _isSaving ? null : _recordAgain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Save note',
                    icon: Icons.check_rounded,
                    loading: _isSaving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A red dot that pulses while recording (still when animations are off).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (MediaQuery.disableAnimationsOf(context)) return dot;
    return FadeTransition(opacity: _pulse, child: dot);
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
