import 'package:latlong2/latlong.dart';

import '../../planner/domain/trip_plan.dart';

/// Fewest verified stops a published tour needs.
const minTourStops = 3;

/// Most stops in one tour (also enforced by the Firestore rules).
const maxTourStops = 15;

/// Longest title and description (also enforced by the rules).
const maxTourTitleLength = 80;
const maxTourDescriptionLength = 500;
const maxTourTipLength = 200;

/// Longest review text (also enforced by the rules).
const maxReviewLength = 500;

class TourStop {
  const TourStop({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.category = '',
    this.tip,
  });

  final String name;
  final double latitude;
  final double longitude;
  final String category;
  final String? tip;

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() => {
    'name': name,
    'lat': latitude,
    'lng': longitude,
    'category': category,
    'tip': ?tip,
  };

  factory TourStop.fromMap(Map<String, dynamic> map) => TourStop(
    name: (map['name'] as String?) ?? '',
    latitude: (map['lat'] as num?)?.toDouble() ?? 0,
    longitude: (map['lng'] as num?)?.toDouble() ?? 0,
    category: (map['category'] as String?) ?? '',
    tip: map['tip'] as String?,
  );
}

/// A walk a traveller published for others to follow.
class CuratedTour {
  const CuratedTour({
    required this.id,
    required this.creatorUid,
    required this.creatorName,
    required this.cityId,
    required this.cityName,
    required this.title,
    required this.description,
    required this.stops,
    required this.createdAt,
  });

  final String id;
  final String creatorUid;
  final String creatorName;

  /// Catalog city id (`varanasi`), for listing tours on the city's page.
  final String cityId;
  final String cityName;
  final String title;
  final String description;
  final List<TourStop> stops;
  final DateTime createdAt;

  /// Straight-line distance stop to stop, in km (the walk is longer).
  double get stopToStopKm {
    const distance = Distance();
    var meters = 0.0;
    for (var i = 1; i < stops.length; i++) {
      meters += distance(stops[i - 1].position, stops[i].position);
    }
    return meters / 1000;
  }

  /// For Firestore. `createdAt` is set by the server on publish.
  Map<String, dynamic> toMap() => {
    'creatorUid': creatorUid,
    'creatorName': creatorName,
    'cityId': cityId,
    'cityName': cityName,
    'title': title,
    'description': description,
    'stops': [for (final s in stops) s.toMap()],
  };

  /// From Firestore data; the repository turns `createdAt` into a
  /// [DateTime] first (null while a new tour's server time is pending).
  factory CuratedTour.fromMap(String id, Map<String, dynamic> map) {
    return CuratedTour(
      id: id,
      creatorUid: (map['creatorUid'] as String?) ?? '',
      creatorName: (map['creatorName'] as String?) ?? 'Explorer',
      cityId: (map['cityId'] as String?) ?? '',
      cityName: (map['cityName'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      stops: [
        for (final s in (map['stops'] as List<dynamic>? ?? const []))
          TourStop.fromMap(Map<String, dynamic>.from(s as Map)),
      ],
      createdAt: (map['createdAt'] as DateTime?) ?? DateTime.now(),
    );
  }
}

/// A rating left on a tour (one per person).
class TourRating {
  const TourRating({
    required this.uid,
    required this.name,
    required this.stars,
    this.review = '',
  });

  final String uid;
  final String name;

  /// 1 to 5.
  final int stars;
  final String review;

  Map<String, dynamic> toMap() => {
    'name': name,
    'stars': stars,
    'review': review,
  };

  factory TourRating.fromMap(String uid, Map<String, dynamic> map) =>
      TourRating(
        uid: uid,
        name: (map['name'] as String?) ?? 'Explorer',
        stars: ((map['stars'] as num?) ?? 0).toInt().clamp(1, 5),
        review: (map['review'] as String?) ?? '',
      );
}

/// Average stars, or null with no ratings.
double? averageStars(List<TourRating> ratings) => ratings.isEmpty
    ? null
    : ratings.fold<int>(0, (n, r) => n + r.stars) / ratings.length;

/// The stops of [day] reached on a counted trip (their place id is in
/// [countedPlaceIds]), in the day's order: only these may be published, so
/// a tour is a walk someone really did. [placeIdOf] gives a stop's place id.
List<TripStop> verifiedTourStops(
  TripDayPlan day,
  Set<String> countedPlaceIds,
  String Function(TripStop) placeIdOf,
) => [
  for (final stop in day.stops)
    if (countedPlaceIds.contains(placeIdOf(stop))) stop,
].take(maxTourStops).toList();

/// [tour] as a one-day trip plan to follow, starting today.
TripPlan tourAsTripPlan(CuratedTour tour, {required DateTime now}) {
  String slot(int i) {
    final share = i / tour.stops.length;
    return share < 0.4
        ? 'Morning'
        : share < 0.75
        ? 'Afternoon'
        : 'Evening';
  }

  return TripPlan(
    id: 'tour-${tour.id}-${now.millisecondsSinceEpoch}',
    title: tour.title,
    destination: tour.cityName,
    cityId: tour.cityId.isEmpty ? null : tour.cityId,
    daysCount: 1,
    createdAt: now,
    overview: '${tour.description}\n\nA community tour by ${tour.creatorName}.',
    days: [
      TripDayPlan(
        dayNumber: 1,
        title: tour.title,
        stops: [
          for (final (i, s) in tour.stops.indexed)
            TripStop(
              id: 'tour-stop-$i',
              placeName: s.name,
              description: '',
              timeSlot: slot(i),
              durationMinutes: 60,
              latitude: s.latitude,
              longitude: s.longitude,
              category: s.category,
              tip: s.tip,
            ),
        ],
      ),
    ],
  );
}
