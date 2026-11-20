import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Long side of the viewing copy members download.
const albumViewSize = 2048;

/// Long side of the grid thumbnail.
const albumThumbSize = 400;

/// The two copies uploaded for an album photo. Both are re-encoded JPEGs
/// with **no EXIF at all**, so the camera's GPS position never leaves the
/// phone inside the file (where it was taken is shared, if at all, only as
/// a separate field the uploader chose to include).
class AlbumCopies {
  const AlbumCopies({required this.view, required this.thumb});
  final Uint8List view;
  final Uint8List thumb;
}

/// Makes the viewing copy and thumbnail of the photo at [path], off the UI
/// thread. Throws [FileSystemException] if the file is gone and
/// [FormatException] if it isn't a readable image.
Future<AlbumCopies> makeAlbumCopies(String path) =>
    Isolate.run(() => makeAlbumCopiesSync(File(path).readAsBytesSync()));

AlbumCopies makeAlbumCopiesSync(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Not an image.');
  // Turn the photo upright first: the orientation flag goes with the EXIF.
  final upright = img.bakeOrientation(decoded);
  return AlbumCopies(
    view: _jpeg(_fit(upright, albumViewSize), quality: 82),
    thumb: _jpeg(_fit(upright, albumThumbSize), quality: 72),
  );
}

/// A copy of the photo with no EXIF (no location, no camera details), for
/// sharing out when the user hides where it was taken. Same size as the
/// original.
Future<Uint8List> withoutMetadata(String path) => Isolate.run(() {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('Not an image.');
  return _jpeg(img.bakeOrientation(decoded), quality: 90);
});

img.Image _fit(img.Image image, int longSide) {
  if (image.width <= longSide && image.height <= longSide) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: longSide,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: longSide,
          interpolation: img.Interpolation.average,
        );
}

Uint8List _jpeg(img.Image image, {required int quality}) {
  final clean = img.Image.from(image)..exif = img.ExifData();
  return img.encodeJpg(clean, quality: quality);
}
