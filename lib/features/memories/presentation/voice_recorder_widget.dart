import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
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
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
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
    });

    setState(() {
      _isRecording = true;
      _recordedPath = path;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    _ticker?.cancel();
    _recordedAt = DateTime.now();
    _recordedWhere = ref
        .read(locationServiceProvider)
        .getCurrentLocation(acceptRecent: true);
    setState(() {
      _isRecording = false;
      _recordedPath = path ?? _recordedPath;
    });
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

  Future<void> _discard() async {
    await _player.stop();
    await _deleteRecording();
    if (mounted) Navigator.of(context).pop();
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
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _recordedPath != null && !_isRecording;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isRecording
                ? 'Recording...'
                : (hasRecording ? 'Preview' : 'Voice Memory'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _formatDuration(_elapsed),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: _isRecording ? Colors.red : AppTheme.forest,
            ),
          ),
          const SizedBox(height: 24),
          if (!_isRecording && !hasRecording)
            FloatingActionButton.large(
              onPressed: _startRecording,
              shape: const CircleBorder(),
              child: const Icon(Icons.mic),
            )
          else if (_isRecording)
            FloatingActionButton.large(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: _stopRecording,
              child: const Icon(Icons.stop),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.forest,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _togglePlayback,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _isSaving ? null : _recordAgain,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Record again'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _isSaving ? null : _discard,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Save'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
