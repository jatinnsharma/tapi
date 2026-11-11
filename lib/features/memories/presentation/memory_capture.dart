import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/memory_repository.dart';
import '../domain/memory_model.dart';
import 'camera_screen.dart';
import 'media_review.dart';
import 'voice_recorder_widget.dart';

/// Longest video you can record from the app (picked videos have no limit
/// here, but sharing is capped at 50 MB).
const _maxVideoLength = Duration(minutes: 1);

/// Bottom sheet with every way to add a memory: take a photo, pick photos
/// from the gallery, record a video, pick a video, or record a voice note.
/// Resolves to how many memories were saved (0 if the user backed out).
Future<int> showAddMemorySheet(
  BuildContext context, {
  String? adventureId,
}) async {
  final saved = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _AddMemorySheet(adventureId: adventureId),
  );
  return saved ?? 0;
}

class _AddMemorySheet extends ConsumerStatefulWidget {
  const _AddMemorySheet({this.adventureId});

  final String? adventureId;

  @override
  ConsumerState<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends ConsumerState<_AddMemorySheet> {
  bool _busy = false;

  void _finish(int saved) {
    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _takePhoto() async {
    final memory = await Navigator.of(context).push<Memory>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(adventureId: widget.adventureId),
      ),
    );
    _finish(memory == null ? 0 : 1);
  }

  Future<void> _voiceNote() async {
    final memory = await showVoiceRecorderSheet(
      context,
      adventureId: widget.adventureId,
    );
    _finish(memory == null ? 0 : 1);
  }

  Future<void> _pickPhotos() => _addReviewed(
    choose: () async => [
      for (final f in await ImagePicker().pickMultiImage()) f,
    ],
    type: MemoryType.photo,
    fromCamera: false,
    retakeLabel: 'Choose again',
  );

  Future<void> _recordVideo() => _addReviewed(
    choose: () async {
      final f = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        maxDuration: _maxVideoLength,
      );
      return [?f];
    },
    type: MemoryType.video,
    fromCamera: true,
    retakeLabel: 'Record again',
  );

  Future<void> _pickVideo() => _addReviewed(
    choose: () async {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
      return [?f];
    },
    type: MemoryType.video,
    fromCamera: false,
    retakeLabel: 'Choose another',
  );

  /// Records or picks, shows the result for review, and saves only what the
  /// user keeps. "Again" repeats the pick or recording.
  ///
  /// [fromCamera] files were just made by the app, so a discarded one is
  /// deleted. Files picked from the gallery belong to the user and are never
  /// deleted.
  Future<void> _addReviewed({
    required Future<List<XFile>> Function() choose,
    required MemoryType type,
    required bool fromCamera,
    required String retakeLabel,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final location = ref.read(locationServiceProvider);

    Future<void> discard(List<XFile> files) async {
      if (!fromCamera) return;
      for (final f in files) {
        try {
          await File(f.path).delete();
        } catch (_) {}
      }
    }

    try {
      while (true) {
        final files = await choose();
        if (files.isEmpty) return; // backed out of the picker or recorder

        // Time and place are those of the recording, not of the moment the
        // user accepts it.
        final capturedAt = DateTime.now();
        final where = location.getCurrentLocation(acceptRecent: true);

        if (!mounted) return;
        final outcome = await navigator.push<ReviewOutcome>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => MediaReviewScreen(
              files: [for (final f in files) f.path],
              isVideo: type == MemoryType.video,
              retakeLabel: retakeLabel,
            ),
          ),
        );

        switch (outcome?.choice ?? ReviewChoice.cancel) {
          case ReviewChoice.retake:
            await discard(files);
            continue;
          case ReviewChoice.cancel:
            await discard(files);
            return;
          case ReviewChoice.use:
            final kept = {...outcome!.kept};
            await discard([
              for (final f in files)
                if (!kept.contains(f.path)) f,
            ]);
            if (mounted) setState(() => _busy = true);
            final spot = await where;
            final repository = ref.read(memoryRepositoryProvider);
            for (final file in files.where((f) => kept.contains(f.path))) {
              await repository.saveMemory(
                Memory(
                  id: const Uuid().v4(),
                  type: type,
                  filePath: await persistMemoryFile(file),
                  timestamp: capturedAt,
                  adventureId: widget.adventureId,
                  latitude: spot?.latitude,
                  longitude: spot?.longitude,
                ),
              );
            }
            _finish(kept.length);
            return;
        }
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add that to your memories: $e')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <(IconData, String, String, VoidCallback)>[
      (
        Icons.photo_camera_outlined,
        'Take a photo',
        'Use the camera',
        _takePhoto,
      ),
      (
        Icons.photo_library_outlined,
        'Photos from gallery',
        'Pick one or several',
        _pickPhotos,
      ),
      (
        Icons.videocam_outlined,
        'Record a video',
        'Up to 1 minute',
        _recordVideo,
      ),
      (
        Icons.video_library_outlined,
        'Video from gallery',
        'Pick an existing video',
        _pickVideo,
      ),
      (Icons.mic_none, 'Voice note', 'Record what you see', _voiceNote),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add a memory',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final (icon, title, subtitle, onTap) in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.emerald.withValues(alpha: 0.14),
                    ),
                    child: Icon(icon, color: AppTheme.primaryGreen),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.inkMuted),
                  ),
                  onTap: onTap,
                ),
          ],
        ),
      ),
    );
  }
}

/// Copies a picked or recorded file into the app's own memories folder, so
/// it survives the gallery or camera app cleaning up after itself.
Future<String> persistMemoryFile(XFile file) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docsDir.path, 'memories'));
  if (!await dir.exists()) await dir.create(recursive: true);
  final destination = p.join(
    dir.path,
    '${const Uuid().v4()}${p.extension(file.path)}',
  );
  await File(file.path).copy(destination);
  return destination;
}
