import 'package:latlong2/latlong.dart';

import '../../locations/domain/location.dart';
import 'city.dart';

enum SearchResultType { city, place }

class SearchResult {
  final String title;
  final String subtitle;
  final LatLng location;
  final SearchResultType type;
  final City? city;
  final String? placeId;

  /// What the place is, in words ("Temple", "Lake", "Railway station").
  final String? kind;

  /// The kind as an app category, for icons and the place sheet.
  final LocationCategory category;

  /// Straight-line distance from the user, when known.
  final double? distanceKm;

  /// Set when the result is one of the app's own saved places.
  final ExploreLocation? savedPlace;

  /// Locality and state, for the place sheet.
  final String? locality;
  final String? state;

  const SearchResult({
    required this.title,
    required this.subtitle,
    required this.location,
    required this.type,
    this.city,
    this.placeId,
    this.kind,
    this.category = LocationCategory.city,
    this.distanceKm,
    this.savedPlace,
    this.locality,
    this.state,
  });

  bool get isCity => type == SearchResultType.city;

  SearchResult withDistanceFrom(LatLng? from) => from == null
      ? this
      : SearchResult(
          title: title,
          subtitle: subtitle,
          location: location,
          type: type,
          city: city,
          placeId: placeId,
          kind: kind,
          category: category,
          distanceKm: const Distance()(from, location) / 1000,
          savedPlace: savedPlace,
          locality: locality,
          state: state,
        );

  /// This result as a place the app can show and start a trip to.
  ExploreLocation toExploreLocation() =>
      savedPlace ??
      ExploreLocation(
        id: placeId ?? 'search-${title.toLowerCase()}',
        name: title,
        category: category,
        description: subtitle,
        latitude: location.latitude,
        longitude: location.longitude,
        neighborhood: locality ?? '',
        city: locality ?? '',
        district: locality ?? '',
        region: state ?? '',
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'lat': location.latitude,
    'lng': location.longitude,
    'type': type.name,
    'cityId': city?.id,
    'placeId': placeId,
    'kind': kind,
    'category': category.name,
    'locality': locality,
    'state': state,
  };

  /// A stored result (recent searches). The city is looked up again by the
  /// caller from `cityId`.
  factory SearchResult.fromJson(Map<String, dynamic> json, {City? city}) =>
      SearchResult(
        title: json['title'] as String,
        subtitle: json['subtitle'] as String? ?? '',
        location: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        type: json['type'] == 'city'
            ? SearchResultType.city
            : SearchResultType.place,
        city: city,
        placeId: json['placeId'] as String?,
        kind: json['kind'] as String?,
        category: LocationCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => LocationCategory.city,
        ),
        locality: json['locality'] as String?,
        state: json['state'] as String?,
      );
}
