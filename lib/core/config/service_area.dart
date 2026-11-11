import 'package:latlong2/latlong.dart';

/// Where the app works. The app covers all of India: places can be fetched
/// and explored around wherever the user is, or whichever city they picked.
class ServiceArea {
  ServiceArea._();

  static const String name = 'India';
  static const String chandigarhName = 'Chandigarh';

  /// Default reference center (New Delhi).
  static const LatLng defaultCenter = LatLng(28.6139, 77.2090);

  /// Historical v1 center kept for reference and backward compatibility.
  static const LatLng chandigarhCenter = LatLng(30.7333, 76.7794);

  /// Default center fallback when location is disabled.
  static const LatLng center = defaultCenter;

  /// Default exploration radius around a user or selected city center (in km).
  static const double defaultRadiusKm = 25.0;

  /// Approximate geographic bounds for India.
  static const double minLat = 6.0;
  static const double maxLat = 38.0;
  static const double minLng = 68.0;
  static const double maxLng = 98.0;

  static const Distance _distance = Distance();

  /// Distance from a reference center (defaults to [defaultCenter]).
  static double kmFromCenter(LatLng point, [LatLng? refCenter]) =>
      _distance(refCenter ?? defaultCenter, point) / 1000;

  /// Whether a point lies within the All-India service area.
  static bool contains(LatLng point) {
    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLng &&
        point.longitude <= maxLng;
  }

  static bool containsCoordinates(double latitude, double longitude) =>
      contains(LatLng(latitude, longitude));

  /// Checks if [point] is within [radiusKm] of [centerPoint].
  static bool isNear(
    LatLng point,
    LatLng centerPoint, {
    double radiusKm = defaultRadiusKm,
  }) {
    return (_distance(centerPoint, point) / 1000) <= radiusKm;
  }
}
