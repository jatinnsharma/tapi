import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/map/cached_tile_provider.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('rwe_tiles'));
  tearDown(() => dir.deleteSync(recursive: true));

  File tile(String name, int bytes, DateTime modified) {
    final f = File('${dir.path}/$name')
      ..writeAsBytesSync(List.filled(bytes, 1));
    f.setLastModifiedSync(modified);
    return f;
  }

  test('under the limit: nothing is deleted', () async {
    tile('a.png', 100, DateTime(2026, 1, 1));
    tile('b.png', 100, DateTime(2026, 1, 2));
    final deleted = await CachedTileProvider.pruneTileCache(
      dir,
      maxBytes: 300,
      targetBytes: 150,
    );
    expect(deleted, 0);
    expect(dir.listSync(), hasLength(2));
  });

  test('over the limit: oldest tiles go first, down to the target', () async {
    final oldest = tile('old.png', 100, DateTime(2026, 1, 1));
    final middle = tile('mid.png', 100, DateTime(2026, 1, 2));
    final newest = tile('new.png', 100, DateTime(2026, 1, 3));
    final deleted = await CachedTileProvider.pruneTileCache(
      dir,
      maxBytes: 250,
      targetBytes: 150,
    );
    expect(deleted, 2);
    expect(oldest.existsSync(), isFalse);
    expect(middle.existsSync(), isFalse);
    expect(newest.existsSync(), isTrue);
  });
}
