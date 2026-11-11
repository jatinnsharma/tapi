import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../data/shared_memory_service.dart';
import '../domain/memory_model.dart';
import '../domain/shared_memory.dart';

/// Plays or shows one photo or video, from a file on the phone or a link.
/// Photos zoom with a pinch; videos have play/pause and a progress bar.
class MemoryMedia extends StatefulWidget {
  const MemoryMedia.file({
    super.key,
    required String path,
    required this.isVideo,
  }) : file = path,
       url = null;

  const MemoryMedia.network({
    super.key,
    required String link,
    required this.isVideo,
  }) : url = link,
       file = null;

  final String? file;
  final String? url;
  final bool isVideo;

  @override
  State<MemoryMedia> createState() => _MemoryMediaState();
}

class _MemoryMediaState extends State<MemoryMedia> {
  VideoPlayerController? _video;
  Object? _videoError;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = widget.file != null
        ? VideoPlayerController.file(File(widget.file!))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _video = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _videoError = e);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVideo) {
      return InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: widget.file != null
              ? Image.file(File(widget.file!), fit: BoxFit.contain)
              : Image.network(
                  widget.url!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                  errorBuilder: (_, _, _) => const _MediaError(),
                ),
        ),
      );
    }

    final video = _video;
    if (_videoError != null) return const _MediaError();
    if (video == null || !video.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: video.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(video),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: video,
              builder: (context, value, _) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => value.isPlaying ? video.pause() : video.play(),
                child: AnimatedOpacity(
                  opacity: value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x99000000),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                video,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppTheme.amber,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Could not load this. Check your connection and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

/// One of your own memories, with the controls for sharing it.
class MemoryViewerScreen extends ConsumerStatefulWidget {
  const MemoryViewerScreen({super.key, required this.memory});

  final Memory memory;

  @override
  ConsumerState<MemoryViewerScreen> createState() => _MemoryViewerScreenState();
}

class _MemoryViewerScreenState extends ConsumerState<MemoryViewerScreen> {
  late Memory _memory = widget.memory;
  late MemoryVisibility _choice =
      _memory.visibility ?? MemoryVisibility.friends;
  late final TextEditingController _caption = TextEditingController(
    text: _memory.caption ?? '',
  );
  double? _progress; // null = idle, 0..1 = uploading
  bool _working = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<Memory> Function(String uid, String name) job,
  ) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _working = true;
      _progress = null;
    });
    try {
      final updated = await job(
        user.uid,
        user.email?.split('@').first ?? 'Explorer',
      );
      if (mounted) setState(() => _memory = updated);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not do that: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _share() => _run((uid, name) {
    final caption = _caption.text.trim();
    return ref
        .read(sharedMemoryServiceProvider)
        .share(
          memory: _memory,
          uid: uid,
          fallbackName: name,
          visibility: _choice,
          caption: caption.isEmpty ? null : caption,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
  });

  Future<void> _unshare() => _run(
    (uid, _) => ref
        .read(sharedMemoryServiceProvider)
        .unshare(memory: _memory, uid: uid),
  );

  @override
  Widget build(BuildContext context) {
    final isVideo = _memory.type == MemoryType.video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          isVideo ? 'Video' : 'Photo',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: MemoryMedia.file(path: _memory.filePath, isVideo: isVideo),
          ),
          _SharePanel(
            memory: _memory,
            choice: _choice,
            caption: _caption,
            progress: _progress,
            working: _working,
            onChoice: (v) => setState(() => _choice = v),
            onShare: _share,
            onUnshare: _unshare,
          ),
        ],
      ),
    );
  }
}

class _SharePanel extends ConsumerWidget {
  const _SharePanel({
    required this.memory,
    required this.choice,
    required this.caption,
    required this.progress,
    required this.working,
    required this.onChoice,
    required this.onShare,
    required this.onUnshare,
  });

  final Memory memory;
  final MemoryVisibility choice;
  final TextEditingController caption;
  final double? progress;
  final bool working;
  final ValueChanged<MemoryVisibility> onChoice;
  final VoidCallback onShare;
  final VoidCallback onUnshare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = firebaseReady ? ref.watch(authStateProvider).value : null;

    Widget body;
    if (!firebaseReady) {
      body = const Text(
        'Sharing isn\'t available on this device.',
        style: TextStyle(color: AppTheme.inkMuted),
      );
    } else if (user == null) {
      body = Row(
        children: [
          const Expanded(
            child: Text(
              'Sign in to share this with friends or everyone.',
              style: TextStyle(color: AppTheme.inkMuted),
            ),
          ),
          FilledButton(
            onPressed: () => context.push('/login'),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            child: const Text('Sign in'),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                memory.isShared
                    ? Icons.cloud_done_outlined
                    : Icons.lock_outline,
                size: 20,
                color: memory.isShared ? AppTheme.emerald : AppTheme.inkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  memory.isShared
                      ? 'Shared with ${memory.visibility!.label.toLowerCase()}'
                      : 'Private: only on this phone',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<MemoryVisibility>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.forest,
                selectedForegroundColor: Colors.white,
                foregroundColor: AppTheme.ink,
              ),
              segments: const [
                ButtonSegment(
                  value: MemoryVisibility.friends,
                  icon: Icon(Icons.group_outlined, size: 18),
                  label: Text('Friends'),
                ),
                ButtonSegment(
                  value: MemoryVisibility.public,
                  icon: Icon(Icons.public, size: 18),
                  label: Text('Public'),
                ),
              ],
              selected: {choice},
              onSelectionChanged: working ? null : (s) => onChoice(s.first),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            choice.description,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: caption,
            enabled: !working,
            maxLength: 140,
            decoration: const InputDecoration(
              labelText: 'Caption (optional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          if (working)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.emerald),
                ),
                const SizedBox(height: 6),
                Text(
                  progress == null
                      ? 'Working…'
                      : 'Uploading ${(progress! * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(memory.isShared ? 'Update' : 'Share'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (memory.isShared) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onUnshare,
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Stop sharing'),
                  ),
                ],
              ],
            ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF7FBF5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(top: false, child: body),
    );
  }
}

/// Someone else's shared photo or video.
class SharedMemoryViewerScreen extends StatelessWidget {
  const SharedMemoryViewerScreen({super.key, required this.memory});

  final SharedMemory memory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          memory.displayName,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: MemoryMedia.network(
              link: memory.url,
              isVideo: memory.isVideo,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            color: Colors.black,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (memory.caption != null && memory.caption!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        memory.caption!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      MetaPill(
                        icon: memory.visibility.name == 'public'
                            ? Icons.public
                            : Icons.group_outlined,
                        label: memory.visibility.label,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _date(memory.createdAt),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime t) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${t.day} ${months.elementAt(t.month - 1)} ${t.year}';
  }
}
