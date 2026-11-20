import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/memory_model.dart';
import 'memory_viewer.dart';

/// Photos and videos in a flat 3-column grid (2 px gutters), then voice
/// notes as rows. Tapping a tile opens it full screen.
class MemoriesGrid extends StatelessWidget {
  const MemoriesGrid({super.key, required this.memories, this.onChanged});

  final List<Memory> memories;

  /// Called when a viewer closes, so the caller can refresh (a memory may
  /// have been shared, unshared or deleted there).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final media = memories
        .where((m) => m.type != MemoryType.voiceNote)
        .toList();
    final voiceNotes = memories
        .where((m) => m.type == MemoryType.voiceNote)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (media.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                // 3 across on phones, more on tablets.
                maxCrossAxisExtent: 160,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: media.length,
              itemBuilder: (context, index) {
                final memory = media[index];
                return MemoryThumb(
                  memory: memory,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MemoryViewerScreen(memory: memory),
                      ),
                    );
                    onChanged?.call();
                  },
                );
              },
            ),
          ),
        if (voiceNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppListGroup(
            children: [
              for (final memory in voiceNotes) VoiceMemoryTile(memory: memory),
            ],
          ),
        ],
      ],
    );
  }
}

/// "0:12", "1:05".
String formatClipLength(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// One photo or video in a grid: a small cached thumbnail (decoded at tile
/// size, not full resolution), a play badge and length for videos, and a
/// shared badge. Says what it is to screen readers.
class MemoryThumb extends StatelessWidget {
  const MemoryThumb({super.key, required this.memory, required this.onTap});

  final Memory memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isVideo = memory.type == MemoryType.video;
    final when = DateFormat('d MMM y').format(memory.timestamp);
    final seconds = memory.durationSeconds;
    return Semantics(
      button: true,
      label:
          '${isVideo ? (memory.isSlowMotion ? 'Slow-motion video' : 'Video') : 'Photo'}, $when'
          '${memory.isShared ? ', shared' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final px =
                (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round();
            return Stack(
              fit: StackFit.expand,
              children: [
                if (isVideo)
                  const ColoredBox(color: Color(0xFF1B1F1D))
                else
                  Hero(
                    tag: 'memory-${memory.id}',
                    child: Image.file(
                      File(memory.filePath),
                      fit: BoxFit.cover,
                      cacheWidth: px > 0 ? px : null,
                      frameBuilder: (context, child, frame, sync) =>
                          AnimatedOpacity(
                            opacity: sync || frame != null ? 1 : 0,
                            duration: AppMotion.fast,
                            child: child,
                          ),
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: colors.surfaceMuted,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                if (isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                if (isVideo && seconds != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Tag(
                      formatClipLength(seconds),
                      icon: memory.isSlowMotion
                          ? Icons.slow_motion_video_rounded
                          : null,
                      tone: TagTone.onImage,
                    ),
                  ),
                if (memory.isShared)
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: Tag(
                      '',
                      icon: Icons.cloud_done_outlined,
                      tone: TagTone.onImage,
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

class VoiceMemoryTile extends StatefulWidget {
  const VoiceMemoryTile({super.key, required this.memory});

  final Memory memory;

  @override
  State<VoiceMemoryTile> createState() => _VoiceMemoryTileState();
}

class _VoiceMemoryTileState extends State<VoiceMemoryTile> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }
    await _player.play(DeviceFileSource(widget.memory.filePath));
    setState(() => _isPlaying = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.memory.durationSeconds ?? 0;
    final when = DateFormat('d MMM y').format(widget.memory.timestamp);
    return AppListTile(
      leading: IconButton.filledTonal(
        onPressed: _toggle,
        tooltip: _isPlaying ? 'Stop' : 'Play voice note',
        icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
      ),
      title: 'Voice note',
      subtitle: '$when · ${formatClipLength(duration)}',
      onTap: _toggle,
    );
  }
}
