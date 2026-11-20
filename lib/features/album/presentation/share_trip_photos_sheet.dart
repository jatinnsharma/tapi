import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/media_shell.dart';
import '../data/album_queue_repository.dart';
import '../data/photo_processing.dart';
import '../domain/album_photo.dart';

/// Sends your trip photos anywhere through the phone's share sheet
/// (WhatsApp, Telegram, email...). Nothing is uploaded by the app: the
/// chosen app sends them. Photos not shared yet are picked to start with,
/// and location is removed unless you choose to keep it.
Future<void> showShareTripPhotosSheet(
  BuildContext context, {
  required String tripTitle,
  required List<QueuedPhoto> photos,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ShareTripPhotos(tripTitle: tripTitle, photos: photos),
  );
}

/// The photos to pick at first: the ones not sent out yet, or all of them
/// when everything has been sent before.
Set<String> initialShareSelection(List<QueuedPhoto> photos) {
  final fresh = {
    for (final ph in photos)
      if (ph.sharedOutAt == null) ph.id,
  };
  return fresh.isEmpty ? {for (final ph in photos) ph.id} : fresh;
}

/// "Varanasi · 12 photos".
String defaultShareCaption(String tripTitle, int count) =>
    '$tripTitle · $count ${count == 1 ? 'photo' : 'photos'}';

class _ShareTripPhotos extends ConsumerStatefulWidget {
  const _ShareTripPhotos({required this.tripTitle, required this.photos});

  final String tripTitle;
  final List<QueuedPhoto> photos;

  @override
  ConsumerState<_ShareTripPhotos> createState() => _ShareTripPhotosState();
}

class _ShareTripPhotosState extends ConsumerState<_ShareTripPhotos> {
  late final Set<String> _selected = initialShareSelection(widget.photos);
  late final TextEditingController _caption = TextEditingController(
    text: defaultShareCaption(widget.tripTitle, _selected.length),
  );
  bool _hideLocation = true;
  bool _working = false;
  String? _error;

  int get _newCount => widget.photos.where((p) => p.sharedOutAt == null).length;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
  });

  Future<void> _share() async {
    final chosen = widget.photos
        .where((p) => _selected.contains(p.id))
        .toList();
    if (chosen.isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final files = <XFile>[];
      final tmp = await getTemporaryDirectory();
      for (final photo in chosen) {
        if (!_hideLocation) {
          files.add(XFile(photo.filePath, mimeType: 'image/jpeg'));
          continue;
        }
        // A clean copy: no location or camera details inside the file.
        final bytes = await withoutMetadata(photo.filePath);
        final out = File(p.join(tmp.path, 'tabi-share-${photo.id}.jpg'));
        await out.writeAsBytes(bytes, flush: true);
        files.add(XFile(out.path, mimeType: 'image/jpeg'));
      }
      final caption = _caption.text.trim();
      final result = await SharePlus.instance.share(
        ShareParams(files: files, text: caption.isEmpty ? null : caption),
      );
      if (result.status != ShareResultStatus.dismissed) {
        final repository = ref.read(albumQueueRepositoryProvider);
        final now = DateTime.now();
        for (final photo in chosen) {
          await repository.save(photo.copyWith(sharedOutAt: now));
        }
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Couldn\'t prepare the photos. Some may no longer be on '
              'this phone.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final photos = widget.photos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Share trip photos', style: text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              photos.isEmpty
                  ? 'Add photos to the album first.'
                  : _newCount == 0
                  ? 'You\'ve shared all of these before.'
                  : '$_newCount new since you last shared.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          if (photos.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  AppButton.tertiary(
                    label: 'Select all',
                    onPressed: () => setState(
                      () => _selected.addAll(photos.map((p) => p.id)),
                    ),
                  ),
                  AppButton.tertiary(
                    label: 'Clear',
                    onPressed: () => setState(_selected.clear),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: photos.length,
                itemBuilder: (context, i) {
                  final photo = photos[i];
                  final on = _selected.contains(photo.id);
                  return Semantics(
                    selected: on,
                    button: true,
                    label: 'Photo ${i + 1}${on ? ', selected' : ''}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => _toggle(photo.id),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(photo.filePath),
                            fit: BoxFit.cover,
                            cacheWidth: 240,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: colors.surfaceMuted),
                          ),
                          if (!on) const ColoredBox(color: mediaUnselectedVeil),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(
                              on
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: on
                                  ? Theme.of(context).colorScheme.primary
                                  : mediaOnColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _caption,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('Remove location from photos'),
              subtitle: const Text(
                'Sends clean copies without where they were taken.',
              ),
              value: _hideLocation,
              onChanged: (v) => setState(() => _hideLocation = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: StatusBanner(kind: StatusKind.error, title: _error!),
              ),
          ],
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: AppButton(
                label: _selected.isEmpty
                    ? 'Share'
                    : 'Share ${_selected.length} '
                          '${_selected.length == 1 ? 'photo' : 'photos'}',
                icon: Icons.ios_share_rounded,
                expand: true,
                loading: _working,
                onPressed: _selected.isEmpty ? null : _share,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
