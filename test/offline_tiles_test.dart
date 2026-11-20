import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/offline/domain/tile_math.dart';

void main() {
  test('slippy tile numbers match the standard formula', () {
    // New Delhi at zoom 10: x = 731.62, y = 426.9986 by the standard
    // formula, so tile 731/426.
    expect(lngToTileX(77.2090, 10), 731);
    expect(latToTileY(28.6139, 10), 426);
    // The whole world is one tile at zoom 0.
    expect(lngToTileX(-179, 0), 0);
    expect(latToTileY(80, 0), 0);
  });

  test('a box covers its corners at every zoom, coarse first', () {
    const sw = LatLng(25.28, 82.98), ne = LatLng(25.34, 83.04);
    final tiles = tilesForBox(sw, ne, minZoom: 12, maxZoom: 14);
    expect(tiles.first.z, 12);
    expect(tiles.last.z, 14);
    for (final z in [12, 13, 14]) {
      final xs = tiles.where((t) => t.z == z).map((t) => t.x).toSet();
      final ys = tiles.where((t) => t.z == z).map((t) => t.y).toSet();
      expect(xs, contains(lngToTileX(sw.longitude, z)));
      expect(xs, contains(lngToTileX(ne.longitude, z)));
      expect(ys, contains(latToTileY(sw.latitude, z)));
      expect(ys, contains(latToTileY(ne.latitude, z)));
    }
  });

  test('a city pack is street-level and within the size limit', () {
    final tiles = packTiles(const LatLng(25.3176, 82.9739)); // Varanasi.
    expect(tiles.length, lessThanOrEqualTo(maxTilesPerPack));
    expect(tiles.length, greaterThan(500));
    expect(tiles.map((t) => t.z).reduce((a, b) => a > b ? a : b), packMaxZoom);
    expect(tiles.map(tileKey).toSet(), hasLength(tiles.length)); // No repeats.
  });

  test('the box is the radius each way', () {
    final box = boxAround(const LatLng(25.0, 83.0), 8);
    const d = Distance();
    expect(
      d(const LatLng(25.0, 83.0), LatLng(box.northEast.latitude, 83.0)) / 1000,
      closeTo(8, 0.1),
    );
    expect(
      d(const LatLng(25.0, 83.0), LatLng(25.0, box.northEast.longitude)) / 1000,
      closeTo(8, 0.1),
    );
  });
}
