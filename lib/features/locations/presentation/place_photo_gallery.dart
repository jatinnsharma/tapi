import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/components.dart';
import '../data/place_photos_service.dart';
import '../domain/location.dart';
import 'place_style.dart';

/// Swipeable photos of a place for the top of its sheet. Shows the place's
/// own image (or its category artwork) while photos load, and keeps that if
/// none are found. Tapping a photo opens it full screen.
class PlacePhotoGallery extends ConsumerStatefulWidget {
  const PlacePhotoGallery({
    super.key,
    required this.place,
    this.height = 200,
    this.radius = 24,
  });

  final ExploreLocation place;
  final double height;
  final double radius;

  @override
  ConsumerState<PlacePhotoGallery> createState() => _PlacePhotoGalleryState();
}

class _PlacePhotoGalleryState extends ConsumerState<PlacePhotoGallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(placePhotosProvider(widget.place.photosKey));
    final photos = photosAsync.value ?? const <PlacePhoto>[];

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: photos.isEmpty
            ? _Fallback(place: widget.place, loading: photosAsync.isLoading)
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => openPhotoViewer(context, photos, i),
                      child: _NetworkPhoto(url: photos[i].thumbUrl),
                    ),
                  ),
                  // Count and credit, readable on any photo.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x99000000)],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                photos[_index].credit,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            MetaPill(
                              icon: Icons.photo_library_outlined,
                              label: '${_index + 1} / ${photos.length}',
                              background: Colors.black.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The place's own image, or its category gradient with mountains, plus a
/// shimmer while photos are still loading.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.place, required this.loading});

  final ExploreLocation place;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final url = place.imageUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: place.category.gradient,
            ),
          ),
        ),
        if (url != null && url.isNotEmpty)
          _NetworkPhoto(url: url)
        else
          const CustomPaint(painter: MountainPainter()),
        if (loading)
          const Positioned(
            right: 12,
            bottom: 12,
            child: MetaPill(
              icon: Icons.photo_library_outlined,
              label: 'Finding photos…',
            ),
          ),
      ],
    );
  }
}

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Shimmer(
              child: SkeletonBox(height: double.infinity, radius: 0),
            ),
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white70),
      ),
    );
  }
}

/// Full-screen, swipeable and zoomable photos with their credits.
void openPhotoViewer(
  BuildContext context,
  List<PlacePhoto> photos,
  int initialIndex,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _PhotoViewerScreen(photos: photos, initialIndex: initialIndex),
    ),
  );
}

class _PhotoViewerScreen extends StatefulWidget {
  const _PhotoViewerScreen({required this.photos, required this.initialIndex});

  final List<PlacePhoto> photos;
  final int initialIndex;

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: _NetworkPhoto(
                    url: widget.photos[i].thumbUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.copyright_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${photo.credit}\nvia Wikimedia Commons',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
