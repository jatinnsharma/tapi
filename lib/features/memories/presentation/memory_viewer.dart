import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/media_shell.dart';
import '../../../core/ui/confirm_destructive.dart';
import '../../../core/ui/friendly_error.dart';
import '../../auth/application/auth_service.dart';
import '../../auth/application/display_name_provider.dart';
import '../data/memory_repository.dart';
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
    this.playbackSpeed = 1,
  }) : file = path,
       url = null;

  const MemoryMedia.network({
    super.key,
    required String link,
    required this.isVideo,
    this.playbackSpeed = 1,
  }) : url = link,
       file = null;

  final String? file;
  final String? url;
  final bool isVideo;

  /// Below 1 for slow-motion videos (they're recorded at a high frame rate
  /// and slowed down here).
  final double playbackSpeed;

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
      if (widget.playbackSpeed != 1) {
        try {
          await controller.setPlaybackSpeed(widget.playbackSpeed);
        } catch (_) {
          // This phone can't play slowed: normal speed.
        }
      }
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
              ? Image.file(
                  File(widget.file!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const _MediaError(local: true),
                )
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
    if (_videoError != null) return _MediaError(local: widget.file != null);
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
  const _MediaError({this.local = false});

  /// A file on this phone (missing or unreadable), not a download.
  final bool local;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          local
              ? 'This file can\'t be opened. It may have been deleted.'
              : 'Couldn\'t load this. Check your connection and try again.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

/// One of your own memories, full screen. Tap to hide the controls.
/// Share (the phone's share sheet), Post (friends or public) and Delete sit
/// in a bar at the bottom; posting options open in a sheet.
class MemoryViewerScreen extends ConsumerStatefulWidget {
  const MemoryViewerScreen({super.key, required this.memory});

  final Memory memory;

  @override
  ConsumerState<MemoryViewerScreen> createState() => _MemoryViewerScreenState();
}

class _MemoryViewerScreenState extends ConsumerState<MemoryViewerScreen> {
  late Memory _memory = widget.memory;
  bool _chrome = true;

  /// Slow-motion videos play slowed unless switched to normal speed.
  bool _normalSpeed = false;

  String get _title => DateFormat('d MMM y · h:mm a').format(_memory.timestamp);

  Future<void> _shareOut() async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(_memory.filePath)]),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t open the share sheet.')),
      );
    }
  }

  Future<void> _post() async {
    // The outer (light) context: the sheet isn't part of the dark viewer.
    final updated = await showModalBottomSheet<Memory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PostSheet(memory: _memory),
    );
    if (updated != null && mounted) setState(() => _memory = updated);
  }

  Future<void> _delete() async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete this memory?',
      message: _memory.isShared
          ? 'It will be removed from this phone. Stop sharing it first if '
                'you want it gone for others too.'
          : 'It will be removed from this phone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(memoryRepositoryProvider).deleteMemory(_memory.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t delete it. ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _memory.type == MemoryType.video;
    final canPost = ref.watch(firebaseReadyProvider);
    return MediaShell(
      title: _title,
      chromeVisible: _chrome,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _chrome = !_chrome),
        child: Hero(
          tag: 'memory-${_memory.id}',
          child: MemoryMedia.file(
            // A new player when the speed changes.
            key: ValueKey(_normalSpeed),
            path: _memory.filePath,
            isVideo: isVideo,
            playbackSpeed: _normalSpeed ? 1 : (_memory.playbackSpeed ?? 1),
          ),
        ),
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_memory.isSlowMotion) ...[
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _normalSpeed = !_normalSpeed),
                icon: Icon(
                  _normalSpeed
                      ? Icons.slow_motion_video_rounded
                      : Icons.speed_rounded,
                ),
                label: Text(
                  _normalSpeed
                      ? 'Play in slow motion'
                      : 'Slow motion · play at normal speed',
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (_memory.isShared) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_done_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Shared with ${_memory.visibility!.label.toLowerCase()}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MediaAction(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onPressed: _shareOut,
              ),
              if (canPost)
                _MediaAction(
                  icon: Icons.public_rounded,
                  label: _memory.isShared ? 'Posted' : 'Post',
                  onPressed: _post,
                ),
              _MediaAction(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                onPressed: _delete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An icon with its label under it, for the viewer's bottom bar.
class _MediaAction extends StatelessWidget {
  const _MediaAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onPressed,
        radius: 36,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 56),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post a memory to friends or everyone, with a caption, or stop sharing
/// it. Pops the updated memory.
class _PostSheet extends ConsumerStatefulWidget {
  const _PostSheet({required this.memory});

  final Memory memory;

  @override
  ConsumerState<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends ConsumerState<_PostSheet> {
  late Memory _memory = widget.memory;
  late MemoryVisibility _choice =
      _memory.visibility ?? MemoryVisibility.friends;
  late final TextEditingController _caption = TextEditingController(
    text: _memory.caption ?? '',
  );
  double? _progress; // null = idle, 0..1 = uploading
  bool _working = false;
  String? _error;

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
    // The name you chose, not part of your email address.
    final name = ref.read(displayNameProvider) ?? 'Explorer';
    setState(() {
      _working = true;
      _progress = null;
      _error = null;
    });
    try {
      final updated = await job(user.uid, name);
      if (!mounted) return;
      _memory = updated;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
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
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final user = ref.watch(authStateProvider).value;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _memory.isShared ? 'Shared' : 'Post this memory',
            style: text.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _memory.isShared
                ? 'Shared with ${_memory.visibility!.label.toLowerCase()}.'
                : 'Private: only on this phone until you post it.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (user == null) ...[
            AppButton(
              label: 'Sign in to post',
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/login');
              },
            ),
          ] else ...[
            SegmentedButton<MemoryVisibility>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: MemoryVisibility.friends,
                  icon: Icon(Icons.group_outlined, size: 18),
                  label: Text('Friends'),
                ),
                ButtonSegment(
                  value: MemoryVisibility.public,
                  icon: Icon(Icons.public, size: 18),
                  label: Text('Everyone'),
                ),
              ],
              selected: {_choice},
              onSelectionChanged: _working
                  ? null
                  : (v) => setState(() => _choice = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              _choice.description,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caption,
              enabled: !_working,
              maxLength: 140,
              decoration: const InputDecoration(
                labelText: 'Caption (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              StatusBanner(
                kind: StatusKind.error,
                title: 'Couldn\'t post',
                message: _error,
              ),
            ],
            const SizedBox(height: 12),
            if (_working) ...[
              LinearProgressIndicator(value: _progress, minHeight: 6),
              const SizedBox(height: 6),
              Text(
                _progress == null
                    ? 'Working…'
                    : 'Uploading ${(_progress! * 100).round()}%',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ] else ...[
              AppButton(
                label: _memory.isShared ? 'Update' : 'Post',
                icon: Icons.cloud_upload_outlined,
                expand: true,
                onPressed: _share,
              ),
              if (_memory.isShared) ...[
                const SizedBox(height: 8),
                AppButton.danger(
                  label: 'Stop sharing',
                  expand: true,
                  onPressed: _unshare,
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// Someone else's shared photo or video: who and when on top, the caption
/// below, and Report in the menu.
class SharedMemoryViewerScreen extends ConsumerStatefulWidget {
  const SharedMemoryViewerScreen({super.key, required this.memory});

  final SharedMemory memory;

  @override
  ConsumerState<SharedMemoryViewerScreen> createState() =>
      _SharedMemoryViewerScreenState();
}

class _SharedMemoryViewerScreenState
    extends ConsumerState<SharedMemoryViewerScreen> {
  bool _chrome = true;

  Future<void> _report() async {
    final ok = await confirmDestructive(
      context,
      title: 'Report this post?',
      message:
          'Tell us it breaks the rules (spam, hate, nudity, or unsafe). '
          'Posts reported by several people are hidden.',
      confirmLabel: 'Report',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sharedMemoryServiceProvider).report(widget.memory.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks. We\'ll take a look.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t report it. ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final caption = memory.caption;
    return MediaShell(
      title:
          '${memory.displayName} · '
          '${DateFormat('d MMM y').format(memory.createdAt)}',
      chromeVisible: _chrome,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (_) => _report(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'report', child: Text('Report')),
          ],
        ),
      ],
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _chrome = !_chrome),
        child: Hero(
          tag: 'shared-${memory.id}',
          child: MemoryMedia.network(link: memory.url, isVideo: memory.isVideo),
        ),
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null && caption.isNotEmpty) ...[
            Text(caption, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(
                memory.visibility.name == 'public'
                    ? Icons.public
                    : Icons.group_outlined,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                memory.visibility.label,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
