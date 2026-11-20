import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:real_world_exploration/features/offline/data/offline_pack_store.dart';
import 'package:real_world_exploration/features/offline/domain/tile_math.dart';

const _varanasi = LatLng(25.3176, 82.9739);

void main() {
  late Directory root;
  late List<String> fetched;

  OfflinePackStore store({bool failAll = false}) => OfflinePackStore(
    root: () async => root,
    key: 'test-key',
    fetch: (url) async {
      fetched.add(url);
      if (failAll) throw const SocketException('offline');
      return List.filled(100, 7);
    },
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('rwe_packs');
    fetched = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('downloads every tile once, then finds them offline', () async {
    final s = store();
    final steps = await s
        .download(cityId: 'varanasi', cityName: 'Varanasi', center: _varanasi)
        .toList();
    final total = packTiles(_varanasi).length;
    expect(steps.last, (done: total, total: total));
    expect(fetched, hasLength(total));
    expect(fetched.first, contains('api.maptiler.com'));
    expect(fetched.first, contains('key=test-key'));

    final info = (await s.info('varanasi'))!;
    expect(info.complete, isTrue);
    expect(info.bytes, total * 100);

    final t = packTiles(_varanasi).last;
    expect(await s.tileFile(t.z, t.x, t.y), isNotNull);
    expect(await s.tileFile(0, 0, 0), isNull);
  });

  test(
    'stopping keeps what was done; resuming fetches only the rest',
    () async {
      final s = store();
      var steps = 0;
      await s
          .download(
            cityId: 'varanasi',
            cityName: 'Varanasi',
            center: _varanasi,
            cancelled: () => ++steps > 3,
          )
          .drain<void>();
      final partial = (await s.info('varanasi'))!;
      expect(partial.complete, isFalse);
      expect(partial.tileCount, greaterThan(0));

      fetched.clear();
      await s
          .download(cityId: 'varanasi', cityName: 'Varanasi', center: _varanasi)
          .drain<void>();
      expect(fetched, hasLength(partial.totalTiles - partial.tileCount));
      expect((await s.info('varanasi'))!.complete, isTrue);
    },
  );

  test('failed tiles leave the pack incomplete, to retry later', () async {
    final s = store(failAll: true);
    await s
        .download(
          cityId: 'goa',
          cityName: 'Goa',
          center: const LatLng(15.5, 73.8),
        )
        .drain<void>();
    final info = (await s.info('goa'))!;
    expect(info.tileCount, 0);
    expect(info.complete, isFalse);
  });

  test('delete removes the pack and its tiles', () async {
    final s = store();
    await s
        .download(cityId: 'varanasi', cityName: 'Varanasi', center: _varanasi)
        .drain<void>();
    final t = packTiles(_varanasi).first;
    await s.delete('varanasi');
    expect(await s.info('varanasi'), isNull);
    expect(await s.tileFile(t.z, t.x, t.y), isNull);
    expect(await s.all(), isEmpty);
  });

  test('refuses a pack that would pass the total storage limit', () async {
    final big = Directory('${root.path}/other')..createSync(recursive: true);
    File('${big.path}/pack.json').writeAsStringSync(
      jsonEncode(
        PackInfo(
          cityId: 'other',
          cityName: 'Other',
          tileCount: 1,
          totalTiles: 1,
          bytes: maxTotalPackBytes,
          downloadedAt: DateTime(2026),
        ).toJson(),
      ),
    );
    expect(
      store()
          .download(cityId: 'varanasi', cityName: 'Varanasi', center: _varanasi)
          .drain<void>(),
      throwsA(isA<PackStorageFullException>()),
    );
  });

  test('without a key, packs are not offered', () {
    expect(OfflinePackStore(key: '').available, isFalse);
  });
}
