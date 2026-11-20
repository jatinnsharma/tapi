import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/nearby_places_service.dart';
import '../domain/food.dart';

final foodRepositoryProvider = Provider<FoodRepository>((ref) {
  return FoodRepository(
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
  );
});

/// Signature dishes for a catalog city id, or none.
final signatureDishesProvider =
    FutureProvider.family<List<SignatureDish>, String>(
      (ref, cityId) => ref.watch(foodRepositoryProvider).dishesFor(cityId),
    );

/// How far around a point food spots are fetched, in metres.
const foodSearchRadiusMeters = 1500;

/// Most spots shown at once, nearest first as Overpass returns them.
const maxFoodSpots = 80;

/// How long fetched spots are reused for the same area.
const foodCacheTtl = Duration(minutes: 30);

class FoodRepository {
  FoodRepository({
    required this.dio,
    AssetBundle? bundle,
    this.endpoints = NearbyPlacesService.overpassEndpoints,
    this.clock = DateTime.now,
  }) : _bundle = bundle ?? rootBundle;

  final Dio dio;
  final AssetBundle _bundle;

  /// Overpass servers, tried in order.
  final List<String> endpoints;
  final DateTime Function() clock;

  Map<String, List<SignatureDish>>? _dishes;
  final _spotCache = <String, ({DateTime at, List<FoodSpot> spots})>{};

  static const _userAgent = 'com.example.real_world_exploration';

  Future<List<SignatureDish>> dishesFor(String cityId) async {
    _dishes ??= await _loadDishes();
    return _dishes![cityId] ?? const [];
  }

  Future<Map<String, List<SignatureDish>>> _loadDishes() async {
    final raw = await _bundle.loadString(
      'assets/data/india_signature_dishes.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in json.entries)
        entry.key: [
          for (final d in entry.value as List<dynamic>)
            SignatureDish.fromJson(d as Map<String, dynamic>),
        ],
    };
  }

  /// Named places to eat within [foodSearchRadiusMeters] of a point, from
  /// OpenStreetMap. Reused for [foodCacheTtl] per ~100 m area. Throws when no
  /// Overpass server answers.
  Future<List<FoodSpot>> spotsNear(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    final cached = _spotCache[key];
    if (cached != null && clock().difference(cached.at) < foodCacheTtl) {
      return cached.spots;
    }

    final query =
        '[out:json][timeout:25];('
        'node["amenity"~"^(restaurant|fast_food|cafe|food_court|ice_cream)\$"]'
        '["name"](around:$foodSearchRadiusMeters,$lat,$lng);'
        'node["shop"~"^(confectionery|pastry|bakery)\$"]'
        '["name"](around:$foodSearchRadiusMeters,$lat,$lng);'
        ');out body $maxFoodSpots;';

    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        final response = await dio.post<Map<String, dynamic>>(
          endpoint,
          data: {'data': query},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'User-Agent': _userAgent},
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final elements = response.data?['elements'] as List<dynamic>? ?? [];
        final spots = [
          for (final e in elements)
            ?FoodSpot.fromOverpass(Map<String, dynamic>.from(e as Map)),
        ];
        _spotCache[key] = (at: clock(), spots: spots);
        return spots;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Could not reach the food service: $lastError');
  }
}
