import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../domain/memory_model.dart';
import 'memory_viewer.dart';

class MemoriesGrid extends StatelessWidget {
  const MemoriesGrid({super.key, required this.memories, this.onChanged});

  final List<Memory> memories;

  /// Called when a viewer closes, so the caller can refresh (a memory may
  /// have been shared or unshared there).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    // Photos and videos share one grid.
    final photos = memories
        .where((m) => m.type != MemoryType.voiceNote)
        .toList();
    final voiceNotes = memories
        .where((m) => m.type == MemoryType.voiceNote)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photos.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final memory = photos[index];
              return PressableScale(
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MemoryViewerScreen(memory: memory),
                      ),
                    );
                    onChanged?.call();
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.forest.withValues(alpha: 0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (memory.type == MemoryType.video)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [AppTheme.forest, Color(0xFF17694B)],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            )
                          else
                            Image.file(
                              File(memory.filePath),
                              fit: BoxFit.cover,
                            ),
                          if (memory.isShared)
                            const Positioned(
                              right: 6,
                              bottom: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xB3000000),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.cloud_done_outlined,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (voiceNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final memory in voiceNotes) VoiceMemoryTile(memory: memory),
        ],
      ],
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
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 22,
      child: Row(
        children: [
          IconButton.filled(
            onPressed: _toggle,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.forest,
              foregroundColor: Colors.white,
            ),
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voice note',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${duration}s',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.graphic_eq_rounded, color: AppTheme.emerald),
        ],
      ),
    );
  }
}
