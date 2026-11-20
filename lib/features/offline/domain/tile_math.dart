import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// A city pack covers this far around the city centre.
const packRadiusKm = 8.0;

/// Zoom levels in a pack: 10 (region) to 16 (street level).
const packMinZoom = 10;
const packMaxZoom = 16;

/// A pack never has more tiles than this.
const maxTilesPerPack = 4000;

/// Average size of one 256 px street-map tile, for estimates.
const averageTileBytes = 22 * 1024;

/// All packs together may use at most this much storage.
const maxTotalPackBytes = 500 * 1024 * 1024;

/// One map tile (Web Mercator "slippy map" numbering).
typedef TileXyz = ({int z, int x, int y});

/// The tile column containing [lng] at zoom [z].
int lngToTileX(double lng, int z) =>
    ((lng + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

/// The tile row containing [lat] at zoom [z].
int latToTileY(double lat, int z) {
  final r = lat * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
  return (y * (1 << z)).floor().clamp(0, (1 << z) - 1);
}

/// The box [radiusKm] around [center] (wide enough in longitude at that
/// latitude).
({LatLng southWest, LatLng northEast}) boxAround(
  LatLng center,
  double radiusKm,
) {
  final dLat = radiusKm / 111.32;
  final dLng = radiusKm / (111.32 * math.cos(center.latitude * math.pi / 180));
  return (
    southWest: LatLng(center.latitude - dLat, center.longitude - dLng),
    northEast: LatLng(center.latitude + dLat, center.longitude + dLng),
  );
}

/// Every tile covering the box, zoom [minZoom]..[maxZoom], coarse first.
List<TileXyz> tilesForBox(
  LatLng southWest,
  LatLng northEast, {
  int minZoom = packMinZoom,
  int maxZoom = packMaxZoom,
}) => [
  for (var z = minZoom; z <= maxZoom; z++)
    for (
      var x = lngToTileX(southWest.longitude, z);
      x <= lngToTileX(northEast.longitude, z);
      x++
    )
      // Rows grow southwards: north edge has the smaller row.
      for (
        var y = latToTileY(northEast.latitude, z);
        y <= latToTileY(southWest.latitude, z);
        y++
      )
        (z: z, x: x, y: y),
];

/// The tiles of a city pack: [packRadiusKm] around [center], dropping the
/// most detailed zoom levels until it fits [maxTilesPerPack].
List<TileXyz> packTiles(LatLng center) {
  final box = boxAround(center, packRadiusKm);
  for (var maxZoom = packMaxZoom; maxZoom >= packMinZoom; maxZoom--) {
    final tiles = tilesForBox(box.southWest, box.northEast, maxZoom: maxZoom);
    if (tiles.length <= maxTilesPerPack) return tiles;
  }
  return const [];
}

/// "z_x_y", a tile's file name stem.
String tileKey(TileXyz t) => '${t.z}_${t.x}_${t.y}';
