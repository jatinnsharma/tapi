import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_service.dart';
import '../data/weather_repository.dart';
import '../domain/weather_model.dart';

final currentWeatherProvider = FutureProvider.autoDispose<WeatherData?>((
  ref,
) async {
  final locationService = ref.watch(locationServiceProvider);
  final location = await locationService.getCurrentLocation();
  if (location == null) return null;

  final repository = ref.watch(weatherRepositoryProvider);
  return repository.getCurrentWeather(location.latitude, location.longitude);
});
