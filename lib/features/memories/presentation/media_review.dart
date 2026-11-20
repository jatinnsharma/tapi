import 'package:flutter/material.dart';

import '../../../core/theme/media_shell.dart';

import 'memory_viewer.dart';

/// What the user decided on the review screen.
enum ReviewChoice {
  /// Keep [ReviewOutcome.kept].
  use,

  /// Throw this away and record or pick again.
  retake,

  /// Throw this away and stop (also the ✕ and the back button).
  cancel,
}

class ReviewOutcome {
  const ReviewOutcome(this.choice, [this.kept = const []]);

  final ReviewChoice choice;

  /// The files to keep (only for [ReviewChoice.use]); photos the user removed
  /// during the review are left out.
  final List<String> kept;
}

/// Shows freshly recorded or picked photos or a video before they become
/// memories. Photos can be swiped and individually removed; a video plays.
/// Pops a [ReviewOutcome]; nothing is saved or deleted here.
class MediaReviewScreen extends StatefulWidget {
  const MediaReviewScreen({
    super.key,
    required this.files,
    required this.isVideo,
    this.retakeLabel = 'Retake',
    this.playbackSpeed = 1,
  });

  final List<String> files;
  final bool isVideo;

  /// Text of the button that starts over, e.g. "Record again".
  final String retakeLabel;

  /// Below 1 to preview a slow-motion video slowed.
  final double playbackSpeed;

  @override
  State<MediaReviewScreen> createState() => _MediaReviewScreenState();
}

class _MediaReviewScreenState extends State<MediaReviewScreen> {
  late final List<String> _kept = [...widget.files];
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _pop(ReviewChoice choice) => Navigator.of(
    context,
  ).pop(ReviewOutcome(choice, choice == ReviewChoice.use ? _kept : const []));

  void _removeCurrent() {
    if (_kept.length <= 1) {
      _pop(ReviewChoice.cancel); // removed the last one
      return;
    }
    setState(() {
      _kept.removeAt(_index);
      if (_index >= _kept.length) _index = _kept.length - 1;
    });
  }

  String get _title {
    if (widget.isVideo) {
      return widget.playbackSpeed < 1 ? 'Review slow motion' : 'Review video';
    }
    return _kept.length == 1
        ? 'Review photo'
        : 'Review photos (${_index + 1}/${_kept.length})';
  }

  String get _useLabel {
    if (widget.isVideo) return 'Use video';
    return _kept.length == 1 ? 'Use photo' : 'Use ${_kept.length} photos';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back cancels, the same as the close button.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop(ReviewChoice.cancel);
      },
      child: MediaShell(
        title: _title,
        onClose: () => _pop(ReviewChoice.cancel),
        actions: [
          if (!widget.isVideo && _kept.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Remove this photo',
              onPressed: _removeCurrent,
            ),
        ],
        body: widget.isVideo
            ? MemoryMedia.file(
                path: _kept.first,
                isVideo: true,
                playbackSpeed: widget.playbackSpeed,
              )
            : PageView.builder(
                controller: _pages,
                itemCount: _kept.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => MemoryMedia.file(
                  key: ValueKey(_kept[i]),
                  path: _kept[i],
                  isVideo: false,
                ),
              ),
        bottom: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pop(ReviewChoice.retake),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(widget.retakeLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pop(ReviewChoice.use),
                icon: const Icon(Icons.check_rounded),
                label: Text(_useLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
