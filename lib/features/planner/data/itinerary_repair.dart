import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../locations/domain/location.dart';
import '../domain/trip_plan.dart';

/// Looks a place up by name near the trip's destination.
typedef StopGeocoder = Future<({LatLng point, String placeId})?> Function(
  String name,
);

/// Turns an AI itinerary into one the app can trust: every stop is a real
/// place with a real position in the destination, days are numbered 1..N with
/// exactly the requested count, no place appears twice, and time slots and
/// durations are sane.
///
/// Each stop is placed by, in order:
///  1. its name matching a real place fetched for the destination
///     (Wikipedia / OpenStreetMap), taking that place's id, position and XP;
///  2. geocoding its name within the destination (limited, see
///     [geocodeBudget]);
///  3. the AI's own coordinates, only if they fall within [maxKm] of the
///     destination.
/// A stop none of these can place is dropped; a day left empty is filled
/// from the real places by [fallbackDay].
class ItineraryRepairer {
  ItineraryRepairer({
    required this.places,
    required this.center,
    this.geocode,
    this.maxKm = 40,
    this.geocodeBudget = const Duration(seconds: 10),
  });

  final List<ExploreLocation> places;
  final LatLng center;
  final StopGeocoder? geocode;
  final double maxKm;

  /// Total time allowed for geocoding (Nominatim takes one request a second,
  /// and offline every lookup times out), after which unplaced stops fall
  /// through to step 3.
  final Duration geocodeBudget;

  static const _uuid = Uuid();
  static const _distance = Distance();
  final Stopwatch _geocodeClock = Stopwatch();

  /// Repairs [days] into exactly [daysCount] days. [fallbackDay] builds a day
  /// from real places not yet used; [alreadyUsed] are place ids to avoid
  /// (other days, when regenerating one).
  Future<List<TripDayPlan>> repair(
    List<TripDayPlan> days, {
    required int daysCount,
    required TripDayPlan Function(int dayNumber, Set<String> usedPlaceIds)
    fallbackDay,
    Set<String> alreadyUsed = const {},
  }) async {
    final used = {...alreadyUsed};
    final sorted = [...days]
      ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    final result = <TripDayPlan>[];

    for (var i = 0; i < daysCount; i++) {
      final dayNumber = i + 1;
      final source = i < sorted.length ? sorted[i] : null;
      final stops = <TripStop>[];
      if (source != null) {
        for (final raw in source.stops) {
          final placed = await groundStop(raw);
          if (placed == null || !used.add(placed.placeId!)) continue;
          stops.add(_tidy(placed, stops.length));
        }
      }

      if (source == null || stops.isEmpty) {
        final filler = fallbackDay(dayNumber, used);
        used.addAll(filler.stops.map((s) => s.placeId).whereType<String>());
        result.add(
          source == null
              ? filler.copyWith(dayNumber: dayNumber)
              : source.copyWith(dayNumber: dayNumber, stops: filler.stops),
        );
        continue;
      }
      result.add(source.copyWith(dayNumber: dayNumber, stops: stops));
    }
    return result;
  }

  /// Gives [stop] a real position and place id, or null if it can't be
  /// placed in the destination.
  Future<TripStop?> groundStop(TripStop stop) async {
    final match = bestNameMatch(stop.placeName);
    if (match != null) {
      return stop.copyWith(
        id: _uuid.v4(),
        latitude: match.latitude,
        longitude: match.longitude,
        placeId: match.id,
        xpReward: match.xpReward,
      );
    }

    final lookup = geocode;
    if (lookup != null && _geocodeClock.elapsed < geocodeBudget) {
      _geocodeClock.start();
      try {
        final found = await lookup(stop.placeName);
        if (found != null && _withinArea(found.point)) {
          return stop.copyWith(
            id: _uuid.v4(),
            latitude: found.point.latitude,
            longitude: found.point.longitude,
            placeId: found.placeId,
          );
        }
      } catch (_) {
      } finally {
        _geocodeClock.stop();
      }
    }

    if (stop.hasValidCoordinates && _withinArea(stop.coordinates)) {
      return stop.copyWith(id: _uuid.v4(), placeId: stableIdFor(stop));
    }
    return null;
  }

  bool _withinArea(LatLng point) => _distance(center, point) / 1000 <= maxKm;

  /// The fetched place whose name best matches [name], if close enough.
  ExploreLocation? bestNameMatch(String name) {
    final wanted = normalizeName(name);
    if (wanted.isEmpty) return null;
    ExploreLocation? best;
    var bestScore = 0.0;
    for (final place in places) {
      final score = nameSimilarity(wanted, normalizeName(place.name));
      if (score > bestScore) {
        bestScore = score;
        best = place;
      }
    }
    return bestScore >= 0.6 ? best : null;
  }

  /// Fixed time slot wording and a duration between 15 minutes and 8 hours.
  TripStop _tidy(TripStop stop, int index) => stop.copyWith(
    timeSlot: normalizeTimeSlot(stop.timeSlot, index),
    durationMinutes: stop.durationMinutes.clamp(15, 480),
  );

  static const _stopWords = {'the', 'of', 'and', 'a', 'sri', 'shri', 'shree'};

  /// Lowercase words without punctuation or filler words. Keeps Devanagari.
  static String normalizeName(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ]+'), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty && !_stopWords.contains(w))
      .join(' ');

  /// 1 for the same name, 0.85 when one contains the other ("Assi Ghat" in
  /// "Assi Ghat Varanasi"), otherwise the share of words in common.
  static double nameSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final shorter = a.length < b.length ? a : b;
    if (shorter.length >= 4 && (a.contains(b) || b.contains(a))) return 0.85;
    final wa = a.split(' ').toSet();
    final wb = b.split(' ').toSet();
    return wa.intersection(wb).length / wa.union(wb).length;
  }

  /// "Morning", "Afternoon" or "Evening" from whatever the AI wrote (English
  /// or Hindi); by position when it's unrecognisable.
  static String normalizeTimeSlot(String raw, int index) {
    final s = raw.toLowerCase();
    if (s.contains('morn') || s.contains('sunrise') || s.contains('सुबह')) {
      return 'Morning';
    }
    if (s.contains('after') ||
        s.contains('noon') ||
        s.contains('lunch') ||
        s.contains('दोपहर')) {
      return 'Afternoon';
    }
    if (s.contains('even') ||
        s.contains('sunset') ||
        s.contains('night') ||
        s.contains('शाम') ||
        s.contains('रात')) {
      return 'Evening';
    }
    return switch (index) {
      0 => 'Morning',
      1 => 'Afternoon',
      _ => 'Evening',
    };
  }

  /// A stable id for a place known only by name and position, so the same
  /// place gets the same id (and counts as visited) across trips.
  static String stableIdFor(TripStop stop) {
    final slug = stop.placeName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final where =
        '${stop.latitude.toStringAsFixed(3)}_${stop.longitude.toStringAsFixed(3)}';
    return slug.isEmpty ? 'plan-$where' : 'plan-$slug-$where';
  }
}
