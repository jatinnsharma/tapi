import 'package:latlong2/latlong.dart';

import '../../../core/utils/polyline_codec.dart';

/// Who may see a user's exploration footprint (route history + visited
/// places). Private is the default: nothing is shared until the user opts in.
enum FootprintVisibility {
  private,
  friends,
  public;

  String get label {
    switch (this) {
      case FootprintVisibility.private:
        return 'Private';
      case FootprintVisibility.friends:
        return 'Friends';
      case FootprintVisibility.public:
        return 'Public';
    }
  }

  String get description {
    switch (this) {
      case FootprintVisibility.private:
        return 'Only you can see your routes and visited places. Nothing is stored online.';
      case FootprintVisibility.friends:
        return 'Your accepted friends can open your map.';
      case FootprintVisibility.public:
        return 'Any signed-in explorer can open your map.';
    }
  }

  static FootprintVisibility fromName(Object? name) {
    return FootprintVisibility.values.firstWhere(
      (v) => v.name == name,
      orElse: () => FootprintVisibility.private,
    );
  }
}

/// A place the user has visited, as shown on someone else's footprint map.
class FootprintPlace {
  const FootprintPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// `LocationCategory.name` of the place.
  final String category;

  LatLng get point => LatLng(latitude, longitude);

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'category': category,
  };

  factory FootprintPlace.fromMap(Map<String, Object?> map) {
    return FootprintPlace(
      id: map['id'] as String,
      name: map['name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      category: (map['category'] as String?) ?? 'nature',
    );
  }
}

/// Firestore doc `footprints/{uid}`: a compact, shareable copy of a user's
/// route history (as encoded polylines) and visited places, plus who may
/// read it. When [visibility] is private the lists are always empty.
class Footprint {
  const Footprint({
    required this.uid,
    required this.displayName,
    required this.visibility,
    required this.updatedAt,
    this.routes = const [],
    this.places = const [],
  });

  final String uid;
  final String displayName;
  final FootprintVisibility visibility;
  final DateTime updatedAt;

  /// One encoded polyline per completed adventure.
  final List<String> routes;
  final List<FootprintPlace> places;

  List<List<LatLng>> get decodedRoutes => [
    for (final route in routes)
      if (route.isNotEmpty) PolylineCodec.decode(route),
  ];

  Map<String, Object?> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'visibility': visibility.name,
    'updatedAt': updatedAt.toIso8601String(),
    'routes': routes,
    'places': [for (final place in places) place.toMap()],
  };

  factory Footprint.fromMap(Map<String, Object?> map) {
    return Footprint(
      uid: map['uid'] as String,
      displayName: (map['displayName'] as String?) ?? 'Explorer',
      visibility: FootprintVisibility.fromName(map['visibility']),
      updatedAt:
          DateTime.tryParse((map['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
      routes: [
        for (final r in (map['routes'] as List? ?? const [])) r as String,
      ],
      places: [
        for (final p in (map['places'] as List? ?? const []))
          FootprintPlace.fromMap(Map<String, Object?>.from(p as Map)),
      ],
    );
  }
}
