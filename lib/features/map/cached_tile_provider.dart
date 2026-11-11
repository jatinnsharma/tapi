import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';

class CachedTileProvider extends TileProvider {
  static final Dio _dio = Dio();
  static String? _cacheDirectory;
  static bool _isInit = false;

  static Future<void> _initCache() async {
    if (_isInit) return;
    final dir = await getApplicationDocumentsDirectory();
    _cacheDirectory = p.join(dir.path, 'map_tiles_cache');
    final dirFile = Directory(_cacheDirectory!);
    if (!await dirFile.exists()) {
      await dirFile.create(recursive: true);
    }
    _isInit = true;
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImageProvider(coordinates, options);
  }
}

class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final TileCoordinates coordinates;
  final TileLayer options;

  _CachedTileImageProvider(this.coordinates, this.options);

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty<_CachedTileImageProvider>('Image provider', this),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    _CachedTileImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      final url = options.urlTemplate!
          .replaceAll('{z}', coordinates.z.toString())
          .replaceAll('{x}', coordinates.x.toString())
          .replaceAll('{y}', coordinates.y.toString());

      if (CachedTileProvider._cacheDirectory == null) {
        await CachedTileProvider._initCache();
      }

      final filename = '${coordinates.z}_${coordinates.x}_${coordinates.y}.png';
      final file = File(p.join(CachedTileProvider._cacheDirectory!, filename));

      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      }

      // Download
      final response = await CachedTileProvider._dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'User-Agent': 'flutter_map'},
        ),
      );

      final bytes = Uint8List.fromList(response.data!);
      await file.writeAsBytes(bytes);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      // Return empty image on failure so we don't crash the map
      final emptyBytes = Uint8List.fromList([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        6,
        0,
        0,
        0,
        31,
        21,
        196,
        137,
        0,
        0,
        0,
        13,
        73,
        68,
        65,
        84,
        120,
        156,
        99,
        252,
        255,
        255,
        63,
        3,
        3,
        3,
        0,
        13,
        23,
        1,
        189,
        36,
        14,
        219,
        131,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
      ]); // 1x1 transparent png
      final buffer = await ui.ImmutableBuffer.fromUint8List(emptyBytes);
      return decode(buffer);
    } finally {
      chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _CachedTileImageProvider &&
        other.coordinates == coordinates &&
        other.options.urlTemplate == options.urlTemplate;
  }

  @override
  int get hashCode => Object.hash(coordinates, options.urlTemplate);
}
