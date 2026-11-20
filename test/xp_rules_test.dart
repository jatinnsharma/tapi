import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_world_exploration/core/config/xp_rules.dart';
import 'package:real_world_exploration/features/locations/domain/location.dart';

/// Reads `PLACE_XP` and `DEFAULT_PLACE_XP` out of the Cloud Function source.
({Map<String, int> table, int fallback}) _serverTable() {
  final js = File('functions/lib/evaluate_trip.js').readAsStringSync();
  final body = RegExp(r'PLACE_XP = Object\.freeze\(\{([^}]*)\}\)')
      .firstMatch(js)!
      .group(1)!;
  final table = {
    for (final m in RegExp(r'(\w+):\s*(\d+)').allMatches(body))
      m.group(1)!: int.parse(m.group(2)!),
  };
  final fallback = int.parse(
    RegExp(r'DEFAULT_PLACE_XP = (\d+)').firstMatch(js)!.group(1)!,
  );
  return (table: table, fallback: fallback);
}

void main() {
  test("the app's and the server's XP tables are the same", () {
    final server = _serverTable();
    expect(server.table, placeXpByCategory);
    expect(server.fallback, defaultPlaceXp);
  });

  test('every kind of place is priced, within the limits', () {
    for (final c in LocationCategory.values) {
      final xp = placeXpByCategory[c.name];
      expect(xp, isNotNull, reason: c.name);
      expect(xp, inInclusiveRange(minPlaceXp, maxPlaceXp), reason: c.name);
    }
  });

  test('claims outside the limits are clamped', () {
    expect(clampPlaceXp(5000), maxPlaceXp);
    expect(clampPlaceXp(-10), minPlaceXp);
    expect(clampPlaceXp(80), 80);
  });

  test('stored places show what is really paid', () {
    final place = ExploreLocation.fromMap({
      'id': 'old-seed',
      'name': 'Old row',
      'category': 'mystery',
      'description': '',
      'latitude': 30.75,
      'longitude': 76.80,
      'xp_reward': 150,
    });
    expect(place.xpReward, maxPlaceXp);
  });
}
