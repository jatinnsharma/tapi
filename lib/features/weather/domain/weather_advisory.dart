import '../../locations/domain/location.dart';
import 'weather_model.dart';

/// What the weather right now means for going out, and which kinds of place
/// to leave out until it passes.
enum AdvisoryKind {
  /// Thunderstorm: stay near shelter.
  storm,

  /// Heavy rain or snow: slippery trails, swollen water.
  heavyRain,

  /// 40 °C or more in the daytime.
  extremeHeat,

  /// US AQI over 200 ("very unhealthy").
  poorAir,
}

/// Open and exposed places: no shelter from storms or the midday sun.
const _exposed = {
  LocationCategory.trek,
  LocationCategory.mountain,
  LocationCategory.viewpoint,
  LocationCategory.camping,
  LocationCategory.nature,
  LocationCategory.lake,
  LocationCategory.waterfall,
  LocationCategory.hiddenGem,
  LocationCategory.photography,
  LocationCategory.mystery,
};

/// Places where rain or snow brings slips, falls or rising water.
const _slipperyOrWet = {
  LocationCategory.trek,
  LocationCategory.mountain,
  LocationCategory.viewpoint,
  LocationCategory.camping,
  LocationCategory.lake,
  LocationCategory.waterfall,
};

/// Hard physical effort, which bad air makes harmful.
const _strenuous = {
  LocationCategory.trek,
  LocationCategory.mountain,
  LocationCategory.camping,
};

/// Heavy rain, heavy snow and violent showers in Open-Meteo's (WMO) codes.
const _heavyRainCodes = {65, 67, 75, 77, 82, 86};

/// The US AQI above which the air counts as very unhealthy.
const poorAirAqi = 200;

/// The daytime temperature, in °C, from which exposed places are left out.
const extremeHeatCelsius = 40.0;

class WeatherAdvisory {
  const WeatherAdvisory(this.kind, this.title, this.advice, this._avoid);

  final AdvisoryKind kind;

  /// Short, e.g. "Thunderstorm nearby".
  final String title;

  /// One line on what to do.
  final String advice;

  final Set<LocationCategory> _avoid;

  /// Whether places of [category] are fine to go to now.
  bool suits(LocationCategory category) => !_avoid.contains(category);

  /// The advisory for [weather] and the air quality [usAqi] (null when not
  /// known), or null when nothing needs avoiding. The most serious one wins:
  /// storm, then heavy rain, then heat, then air.
  static WeatherAdvisory? from(WeatherData? weather, {int? usAqi}) {
    if (weather != null) {
      final code = weather.weatherCode;
      if (code >= 95) {
        return const WeatherAdvisory(
          AdvisoryKind.storm,
          'Thunderstorm nearby',
          'Showing sheltered places: temples, museums, markets and food.',
          _exposed,
        );
      }
      if (_heavyRainCodes.contains(code)) {
        return const WeatherAdvisory(
          AdvisoryKind.heavyRain,
          'Heavy rain or snow',
          'Trails, waterfalls and viewpoints are left out until it eases.',
          _slipperyOrWet,
        );
      }
      if (weather.isDay && weather.temperature >= extremeHeatCelsius) {
        return WeatherAdvisory(
          AdvisoryKind.extremeHeat,
          'Extreme heat: ${weather.temperature.round()} °C',
          'Exposed spots are best before 11 AM or after 4 PM. Carry water.',
          _exposed,
        );
      }
    }
    if (usAqi != null && usAqi > poorAirAqi) {
      return WeatherAdvisory(
        AdvisoryKind.poorAir,
        'Very unhealthy air (AQI $usAqi)',
        'Treks are left out. Wear a mask outdoors; keep walks short.',
        _strenuous,
      );
    }
    return null;
  }
}
