import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';
import 'package:real_world_exploration/features/weather/domain/weather_advisory.dart';
import 'package:real_world_exploration/features/weather/domain/weather_model.dart';
import 'package:real_world_exploration/features/weather/presentation/weather_advisory_banner.dart';

WeatherData _weather({int code = 0, double temp = 28, bool day = true}) =>
    WeatherData(temperature: temp, windSpeed: 5, weatherCode: code, isDay: day);

void main() {
  test('fine weather and clean air: no advisory, nothing hidden', () {
    expect(WeatherAdvisory.from(_weather(), usAqi: 80), isNull);
    expect(WeatherAdvisory.from(null), isNull);
    // Ordinary rain doesn't hide anything.
    expect(WeatherAdvisory.from(_weather(code: 61)), isNull);
  });

  test('thunderstorm: only sheltered places stay', () {
    final a = WeatherAdvisory.from(_weather(code: 95))!;
    expect(a.kind, AdvisoryKind.storm);
    for (final c in [
      LocationCategory.heritage,
      LocationCategory.food,
      LocationCategory.city,
    ]) {
      expect(a.suits(c), isTrue, reason: c.name);
    }
    for (final c in [
      LocationCategory.viewpoint,
      LocationCategory.waterfall,
      LocationCategory.trek,
      LocationCategory.nature,
    ]) {
      expect(a.suits(c), isFalse, reason: c.name);
    }
  });

  test('heavy rain: trails, water and heights are left out', () {
    final a = WeatherAdvisory.from(_weather(code: 65))!;
    expect(a.kind, AdvisoryKind.heavyRain);
    expect(a.suits(LocationCategory.waterfall), isFalse);
    expect(a.suits(LocationCategory.trek), isFalse);
    expect(a.suits(LocationCategory.nature), isTrue);
    expect(a.suits(LocationCategory.heritage), isTrue);
  });

  test('extreme heat only in the daytime', () {
    final hot = WeatherAdvisory.from(_weather(temp: 43.4))!;
    expect(hot.kind, AdvisoryKind.extremeHeat);
    expect(hot.title, contains('43'));
    expect(hot.suits(LocationCategory.viewpoint), isFalse);
    expect(hot.suits(LocationCategory.food), isTrue);
    expect(WeatherAdvisory.from(_weather(temp: 41, day: false)), isNull);
    expect(WeatherAdvisory.from(_weather(temp: 39.9)), isNull);
  });

  test('very unhealthy air: treks are left out', () {
    final a = WeatherAdvisory.from(_weather(), usAqi: 320)!;
    expect(a.kind, AdvisoryKind.poorAir);
    expect(a.title, contains('320'));
    expect(a.suits(LocationCategory.trek), isFalse);
    expect(a.suits(LocationCategory.heritage), isTrue);
    expect(WeatherAdvisory.from(_weather(), usAqi: 200), isNull);
  });

  test('the most serious condition wins', () {
    expect(
      WeatherAdvisory.from(_weather(code: 95, temp: 42), usAqi: 400)!.kind,
      AdvisoryKind.storm,
    );
    expect(
      WeatherAdvisory.from(_weather(temp: 42), usAqi: 400)!.kind,
      AdvisoryKind.extremeHeat,
    );
  });

  testWidgets('banner: hidden count, and Show all toggles', (tester) async {
    final advisory = WeatherAdvisory.from(_weather(code: 95))!;
    var toggled = 0;
    Widget banner(bool showingAll, int hidden) => MaterialApp(
      home: Scaffold(
        body: WeatherAdvisoryBanner(
          advisory: advisory,
          hiddenCount: hidden,
          showingAll: showingAll,
          onToggle: () => toggled++,
        ),
      ),
    );

    await tester.pumpWidget(banner(false, 6));
    expect(find.text('Thunderstorm nearby'), findsOneWidget);
    expect(find.textContaining('6 places hidden.'), findsOneWidget);
    await tester.tap(find.text('Show all'));
    expect(toggled, 1);

    await tester.pumpWidget(banner(true, 0));
    expect(find.text('Hide unsuitable'), findsOneWidget);

    await tester.pumpWidget(banner(false, 0));
    expect(find.byType(TextButton), findsNothing);
  });
}
