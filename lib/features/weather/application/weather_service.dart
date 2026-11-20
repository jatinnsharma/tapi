import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_service.dart';
import '../data/weather_repository.dart';
import '../domain/weather_advisory.dart';
import '../domain/weather_model.dart';

final currentWeatherProvider = FutureProvider.autoDispose<WeatherData?>((
  ref,
) async {
  final locationService = ref.watch(locationServiceProvider);
  // A recent position is fine for the weather, and instant.
  final location = await locationService.getCurrentLocation(acceptRecent: true);
  if (location == null) return null;

  final repository = ref.watch(weatherRepositoryProvider);
  return repository.getCurrentWeather(location.latitude, location.longitude);
});

/// The weather advisory at a point, rounded to about 1 km so nearby screens
/// share one lookup. Null when the weather is fine, or unknown (offline):
/// nothing is hidden on a guess.
final weatherAdvisoryProvider = FutureProvider.autoDispose
    .family<WeatherAdvisory?, ({double lat, double lng})>((ref, at) async {
      final repository = ref.watch(weatherRepositoryProvider);
      final results = await Future.wait<Object?>([
        repository.getCurrentWeather(at.lat, at.lng),
        repository.getUsAqi(at.lat, at.lng),
      ]);
      return WeatherAdvisory.from(
        results[0] as WeatherData?,
        usAqi: results[1] as int?,
      );
    });

/// [lat], [lng] rounded to 2 decimals (about 1 km), as a provider key.
({double lat, double lng}) weatherKey(double lat, double lng) => (
  lat: (lat * 100).roundToDouble() / 100,
  lng: (lng * 100).roundToDouble() / 100,
);
