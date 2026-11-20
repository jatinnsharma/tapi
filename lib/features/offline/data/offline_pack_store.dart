import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/tile_math.dart';
import '../../../core/ui/friendly_error.dart';

/// MapTiler key for offline packs, passed at build time
/// (`--dart-define=MAPTILER_KEY=...`). Empty: packs are not offered.
const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// MapTiler's 256 px "Streets" raster tiles. Check that your MapTiler plan
/// allows keeping tiles on the device for offline use.
String mapTilerTileUrl(TileXyz t, String key) =>
    'https://api.maptiler.com/maps/streets-v2/256/${t.z}/${t.x}/${t.y}.png'
    '?key=$key';

/// A downloaded (or partly downloaded) city pack.
class PackInfo {
  const PackInfo({
    required this.cityId,
    required this.cityName,
    required this.tileCount,
    required this.totalTiles,
    required this.bytes,
    required this.downloadedAt,
  });

  final String cityId;
  final String cityName;
  final int tileCount;
  final int totalTiles;
  final int bytes;
  final DateTime downloadedAt;

  bool get complete => tileCount >= totalTiles;

  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'cityName': cityName,
    'tileCount': tileCount,
    'totalTiles': totalTiles,
    'bytes': bytes,
    'downloadedAt': downloadedAt.toIso8601String(),
  };

  factory PackInfo.fromJson(Map<String, dynamic> j) => PackInfo(
    cityId: j['cityId'] as String,
    cityName: j['cityName'] as String,
    tileCount: j['tileCount'] as int,
    totalTiles: j['totalTiles'] as int,
    bytes: j['bytes'] as int,
    downloadedAt: DateTime.parse(j['downloadedAt'] as String),
  );
}

/// Progress of a download: tiles done of the total.
typedef PackProgress = ({int done, int total});

/// Thrown when packs would use more than [maxTotalPackBytes].
class PackStorageFullException implements Exception, UserFacingError {
  @override
  String get message =>
      'Offline maps are using all their space. Delete a city first.';

  @override
  String toString() => message;
}

/// City packs on the phone: `offline_packs/<cityId>/z_x_y.png` plus a
/// `pack.json`. One shared instance, so the map's tile provider can look
/// tiles up without Riverpod.
class OfflinePackStore {
  OfflinePackStore({
    Future<Directory> Function()? root,
    Future<List<int>> Function(String url)? fetch,
    this.key = mapTilerKey,
  }) : _root = root ?? _defaultRoot,
       _fetch = fetch ?? _dioFetch;

  static final instance = OfflinePackStore();

  final Future<Directory> Function() _root;
  final Future<List<int>> Function(String url) _fetch;
  final String key;

  bool get available => key.isNotEmpty;

  /// tile key -> file, across all packs; built on first lookup.
  Map<String, String>? _index;

  static Future<Directory> _defaultRoot() async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'offline_packs'),
  );

  static final _dio = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  static Future<List<int>> _dioFetch(String url) async =>
      (await _dio.get<List<int>>(url)).data!;

  Future<Directory> _dirFor(String cityId) async =>
      Directory(p.join((await _root()).path, cityId));

  Future<PackInfo?> info(String cityId) async {
    final file = File(p.join((await _dirFor(cityId)).path, 'pack.json'));
    if (!await file.exists()) return null;
    try {
      return PackInfo.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<PackInfo>> all() async {
    final root = await _root();
    if (!await root.exists()) return const [];
    final packs = <PackInfo>[];
    await for (final d in root.list()) {
      if (d is Directory) {
        final i = await info(p.basename(d.path));
        if (i != null) packs.add(i);
      }
    }
    return packs;
  }

  /// Downloads (or finishes downloading) [cityId]'s pack around [center],
  /// reporting progress. Tiles already on the phone are skipped. Stops
  /// early when [cancelled] returns true; what's done so far is kept.
  Stream<PackProgress> download({
    required String cityId,
    required String cityName,
    required LatLng center,
    bool Function()? cancelled,
    int parallel = 4,
  }) async* {
    if (!available) throw StateError('No MapTiler key.');
    final tiles = packTiles(center);
    final dir = await _dirFor(cityId);
    await dir.create(recursive: true);

    final others = (await all()).where((x) => x.cityId != cityId);
    final usedElsewhere = others.fold<int>(0, (n, x) => n + x.bytes);
    if (usedElsewhere + tiles.length * averageTileBytes > maxTotalPackBytes) {
      throw PackStorageFullException();
    }

    var bytes = 0;
    var done = 0;
    final todo = <TileXyz>[];
    for (final t in tiles) {
      final f = File(p.join(dir.path, '${tileKey(t)}.png'));
      if (await f.exists()) {
        done++;
        bytes += await f.length();
      } else {
        todo.add(t);
      }
    }
    yield (done: done, total: tiles.length);

    for (var i = 0; i < todo.length; i += parallel) {
      if (cancelled?.call() ?? false) break;
      final batch = todo.skip(i).take(parallel);
      final sizes = await Future.wait(
        batch.map((t) async {
          try {
            final data = await _fetch(mapTilerTileUrl(t, key));
            await File(p.join(dir.path, '${tileKey(t)}.png'))
                .writeAsBytes(data, flush: true);
            return data.length;
          } catch (_) {
            return -1; // Retried next time: the tile is still missing.
          }
        }),
      );
      for (final s in sizes) {
        if (s >= 0) {
          done++;
          bytes += s;
        }
      }
      yield (done: done, total: tiles.length);
    }

    await File(p.join(dir.path, 'pack.json')).writeAsString(
      jsonEncode(
        PackInfo(
          cityId: cityId,
          cityName: cityName,
          tileCount: done,
          totalTiles: tiles.length,
          bytes: bytes,
          downloadedAt: DateTime.now(),
        ).toJson(),
      ),
    );
    _index = null;
  }

  Future<void> delete(String cityId) async {
    final dir = await _dirFor(cityId);
    if (await dir.exists()) await dir.delete(recursive: true);
    _index = null;
  }

  /// The pack file for a tile, from any city, or null.
  Future<File?> tileFile(int z, int x, int y) async {
    final index = _index ??= await _buildIndex();
    final path = index['${z}_${x}_$y'];
    return path == null ? null : File(path);
  }

  Future<Map<String, String>> _buildIndex() async {
    final root = await _root();
    final index = <String, String>{};
    if (!await root.exists()) return index;
    await for (final f in root.list(recursive: true)) {
      if (f is File && f.path.endsWith('.png')) {
        index[p.basenameWithoutExtension(f.path)] = f.path;
      }
    }
    return index;
  }
}
