import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/weather_model.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    ),
  );
});

class WeatherRepository {
  WeatherRepository(this._dio);

  final Dio _dio;

  Future<WeatherData?> getCurrentWeather(
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
          'current_weather': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['current_weather'];
        if (data != null) {
          return WeatherData.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      // In a real app, we'd log this or handle it. For MVP, we return null to fail gracefully.
      return null;
    }
  }

  /// How far ahead Open-Meteo forecasts.
  static const forecastDays = 16;

  /// Daily forecast for [days] days from [start]. Returns null when the trip
  /// is too far ahead (or already over) for a forecast, or on any error. Days
  /// past the forecast window are left out.
  Future<List<DailyForecast>?> getDailyForecast(
    double latitude,
    double longitude, {
    required DateTime start,
    required int days,
  }) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final lastForecastDay = today.add(const Duration(days: forecastDays - 1));
    var from = DateUtils.dateOnly(start);
    var to = from.add(Duration(days: days - 1));
    if (from.isBefore(today)) from = today;
    if (to.isAfter(lastForecastDay)) to = lastForecastDay;
    if (from.isAfter(to)) return null;

    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    try {
      final response = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
          'daily': 'weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
          'timezone': 'auto',
          'start_date': day(from),
          'end_date': day(to),
        },
      );
      final daily = response.data['daily'] as Map<String, dynamic>?;
      if (daily == null) return null;
      final dates = daily['time'] as List<dynamic>;
      final codes = daily['weathercode'] as List<dynamic>;
      final maxes = daily['temperature_2m_max'] as List<dynamic>;
      final mins = daily['temperature_2m_min'] as List<dynamic>;
      final rain = daily['precipitation_probability_max'] as List<dynamic>?;
      return [
        for (var i = 0; i < dates.length; i++)
          if (codes[i] != null && maxes[i] != null && mins[i] != null)
            DailyForecast(
              date: DateTime.parse(dates[i] as String),
              weatherCode: (codes[i] as num).toInt(),
              maxTemp: (maxes[i] as num).toDouble(),
              minTemp: (mins[i] as num).toDouble(),
              rainChance: (rain?[i] as num?)?.toInt(),
            ),
      ];
    } catch (_) {
      return null;
    }
  }
}
