class WeatherData {
  const WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.weatherCode,
    required this.isDay,
  });

  final double temperature;
  final double windSpeed;
  final int weatherCode;
  final bool isDay;

  bool get isSevere =>
      weatherCode >= 71; // Arbitrary threshold: snow, heavy rain, thunderstorms

  String get conditionDescription {
    if (weatherCode == 0) return 'Clear sky';
    if (weatherCode == 1 || weatherCode == 2 || weatherCode == 3) {
      return 'Partly cloudy';
    }
    if (weatherCode == 45 || weatherCode == 48) return 'Fog';
    if (weatherCode >= 51 && weatherCode <= 55) return 'Drizzle';
    if (weatherCode >= 61 && weatherCode <= 65) return 'Rain';
    if (weatherCode >= 71 && weatherCode <= 75) return 'Snow';
    if (weatherCode >= 80 && weatherCode <= 82) return 'Rain showers';
    if (weatherCode >= 95) return 'Thunderstorm';
    return 'Unknown ($weatherCode)';
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['temperature'] as num).toDouble(),
      windSpeed: (json['windspeed'] as num).toDouble(),
      weatherCode: json['weathercode'] as int,
      isDay: json['is_day'] == 1,
    );
  }
}

/// One day of a forecast, for a planned trip's dates.
class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.weatherCode,
    required this.maxTemp,
    required this.minTemp,
    this.rainChance,
  });

  final DateTime date;
  final int weatherCode;
  final double maxTemp;
  final double minTemp;

  /// Highest chance of rain that day, in percent.
  final int? rainChance;

  /// Same wording as [WeatherData.conditionDescription].
  String get conditionDescription => WeatherData(
    temperature: maxTemp,
    windSpeed: 0,
    weatherCode: weatherCode,
    isDay: true,
  ).conditionDescription;
}
