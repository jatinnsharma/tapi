import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/utils/polyline_codec.dart';
import '../application/tracking_service.dart';
import '../domain/directions.dart';

final directionsServiceProvider = Provider<DirectionsService>((ref) {
  return DirectionsService(
    Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
  );
});

/// Turn-by-turn directions from OpenStreetMap-based routing (FOSSGIS's public
/// OSRM servers, no key needed). Unlike the OSRM demo server, these have real
/// walking and cycling profiles rather than car routes.
class DirectionsService {
  DirectionsService(this._dio);

  final Dio _dio;

  static const _userAgent = 'com.example.real_world_exploration';

  Future<RouteDirections> getRoute({
    required LatLng from,
    required LatLng to,
    required String destinationName,
    TravelMode mode = TravelMode.foot,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      // The profile (walking or driving) is chosen by the server path; the
      // segment after "route/v1/" is always "driving" on these servers.
      'https://routing.openstreetmap.de/${mode._server}/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      queryParameters: {
        'steps': 'true',
        // Full route line, polyline-encoded (precision 5, same format as
        // the app's PolylineCodec).
        'overview': 'full',
        'geometries': 'polyline',
      },
      options: Options(
        headers: {'User-Agent': _userAgent},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    final routes = response.data?['routes'] as List<dynamic>?;
    if (response.data?['code'] != 'Ok' || routes == null || routes.isEmpty) {
      throw StateError('No route found.');
    }
    final route = routes.first as Map<String, dynamic>;
    final rawSteps =
        ((route['legs'] as List).first as Map<String, dynamic>)['steps']
            as List<dynamic>;

    final geometry = route['geometry'];
    return RouteDirections(
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      path: geometry is String ? PolylineCodec.decode(geometry) : const [],
      steps: [
        for (final raw in rawSteps)
          _toStep(raw as Map<String, dynamic>, destinationName),
      ],
      driving: mode == TravelMode.car,
    );
  }

  DirectionStep _toStep(Map<String, dynamic> step, String destinationName) {
    final maneuver = step['maneuver'] as Map<String, dynamic>;
    final type = maneuver['type'] as String? ?? 'continue';
    final modifier = maneuver['modifier'] as String?;
    final name = (step['name'] as String?)?.trim() ?? '';
    final exit = maneuver['exit'] as int?;
    final location = maneuver['location'] as List<dynamic>;

    return DirectionStep(
      instruction: _instruction(type, modifier, name, exit, destinationName),
      icon: _icon(type, modifier),
      location: LatLng(
        (location[1] as num).toDouble(),
        (location[0] as num).toDouble(),
      ),
      distanceMeters: (step['distance'] as num).toDouble(),
    );
  }

  String _instruction(
    String type,
    String? modifier,
    String name,
    int? exit,
    String destinationName,
  ) {
    final onto = name.isEmpty ? '' : ' onto $name';
    final direction = _direction(modifier);

    switch (type) {
      case 'depart':
        return name.isEmpty ? 'Start walking' : 'Start walking on $name';
      case 'arrive':
        return 'You have arrived at $destinationName';
      case 'turn':
        return '${_capitalize(direction.turn)}$onto';
      case 'end of road':
        return 'At the end of the road, ${direction.turn}$onto';
      case 'fork':
        return 'Keep ${direction.keep}$onto';
      case 'merge':
        return 'Merge ${direction.keep}$onto';
      case 'roundabout':
      case 'rotary':
        return exit == null
            ? 'Enter the roundabout$onto'
            : 'At the roundabout, take exit $exit$onto';
      case 'new name':
      case 'continue':
      default:
        return modifier == null || modifier == 'straight'
            ? 'Continue straight$onto'
            : '${_capitalize(direction.turn)}$onto';
    }
  }

  ({String turn, String keep}) _direction(String? modifier) {
    switch (modifier) {
      case 'left':
        return (turn: 'turn left', keep: 'left');
      case 'right':
        return (turn: 'turn right', keep: 'right');
      case 'slight left':
        return (turn: 'turn slightly left', keep: 'left');
      case 'slight right':
        return (turn: 'turn slightly right', keep: 'right');
      case 'sharp left':
        return (turn: 'turn sharply left', keep: 'left');
      case 'sharp right':
        return (turn: 'turn sharply right', keep: 'right');
      case 'uturn':
        return (turn: 'make a U-turn', keep: 'straight');
      default:
        return (turn: 'continue straight', keep: 'straight');
    }
  }

  IconData _icon(String type, String? modifier) {
    if (type == 'arrive') return Icons.flag_rounded;
    if (type == 'depart') return Icons.directions_walk_rounded;
    if (type == 'roundabout' || type == 'rotary') {
      return Icons.roundabout_right_rounded;
    }
    switch (modifier) {
      case 'left':
        return Icons.turn_left_rounded;
      case 'right':
        return Icons.turn_right_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'sharp left':
        return Icons.turn_sharp_left_rounded;
      case 'sharp right':
        return Icons.turn_sharp_right_rounded;
      case 'uturn':
        return Icons.u_turn_left_rounded;
      default:
        return Icons.arrow_upward_rounded;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Route from where the user is now to [destination]. Loads once per
/// destination; a failure (offline, no path) surfaces as an error the panel
/// shows with a retry, and never affects the adventure itself.
final routeToDestinationProvider = FutureProvider.autoDispose
    .family<RouteDirections, Destination>((ref, destination) async {
      // Keep the route for the whole trip, even while the tracking screen is
      // closed, so reopening it doesn't need a connection. "Recalculate"
      // replaces it explicitly.
      ref.keepAlive();
      final tracking = ref.read(trackingServiceProvider);
      final last = tracking.routePoints.isEmpty
          ? null
          : tracking.routePoints.last;
      final from = last != null
          ? LatLng(last.latitude, last.longitude)
          : await ref.read(locationServiceProvider).getCurrentLocation();
      if (from == null) {
        throw StateError('Your location isn\'t available yet.');
      }

      return ref
          .read(directionsServiceProvider)
          .getRoute(
            from: from,
            to: destination.point,
            destinationName: destination.name,
            mode:
                ref.watch(travelModeProvider) ??
                autoTravelMode(from, destination.point),
          );
    });

/// The travel mode the user picked for directions, or null for automatic
/// (see [autoTravelMode]). Kept for the session, like Google Maps remembers
/// the last mode. Directions only: how a trip counts doesn't depend on it.
final travelModeProvider = NotifierProvider<TravelModeChoice, TravelMode?>(
  TravelModeChoice.new,
);

class TravelModeChoice extends Notifier<TravelMode?> {
  @override
  TravelMode? build() => null;

  void choose(TravelMode? mode) => state = mode;
}

/// Places beyond this straight-line distance get driving directions unless
/// the user picks walking.
const autoDriveBeyondMeters = 2500.0;

TravelMode autoTravelMode(LatLng from, LatLng to) =>
    const Distance()(from, to) > autoDriveBeyondMeters
    ? TravelMode.car
    : TravelMode.foot;

/// How a journey could be made, for planning.
enum TravelMode {
  car('routed-car'),
  foot('routed-foot');

  const TravelMode(this._server);
  final String _server;
}

/// Distance and time of a journey by one mode.
class TravelEstimate {
  const TravelEstimate({required this.meters, required this.duration});
  final double meters;
  final Duration duration;
}

/// Journey estimates to a trek's start, by car and on foot. Either may be
/// null when that route couldn't be found (offline, no road).
class JourneyEstimate {
  const JourneyEstimate({this.byCar, this.onFoot});
  final TravelEstimate? byCar;
  final TravelEstimate? onFoot;

  bool get isEmpty => byCar == null && onFoot == null;
}

extension JourneyEstimates on DirectionsService {
  /// Distance and time from [from] to [to] by [mode], without steps.
  Future<TravelEstimate> estimate({
    required LatLng from,
    required LatLng to,
    required TravelMode mode,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://routing.openstreetmap.de/${mode._server}/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      queryParameters: {'overview': 'false'},
      options: Options(
        headers: {'User-Agent': DirectionsService._userAgent},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final routes = response.data?['routes'] as List<dynamic>?;
    if (response.data?['code'] != 'Ok' || routes == null || routes.isEmpty) {
      throw StateError('No route found.');
    }
    final route = routes.first as Map<String, dynamic>;
    return TravelEstimate(
      meters: (route['distance'] as num).toDouble(),
      duration: Duration(seconds: (route['duration'] as num).round()),
    );
  }

  /// One route through [points] in order (an itinerary day): the road path
  /// for the map and each leg's distance and time.
  Future<MultiStopRoute> routeThrough(
    List<LatLng> points, {
    TravelMode mode = TravelMode.car,
  }) async {
    if (points.length < 2) throw ArgumentError('Need at least two points.');
    final coordinates = points
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final response = await _dio.get<Map<String, dynamic>>(
      'https://routing.openstreetmap.de/${mode._server}/route/v1/driving/'
      '$coordinates',
      queryParameters: {'overview': 'full', 'geometries': 'polyline'},
      options: Options(
        headers: {'User-Agent': DirectionsService._userAgent},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final routes = response.data?['routes'] as List<dynamic>?;
    if (response.data?['code'] != 'Ok' || routes == null || routes.isEmpty) {
      throw StateError('No route found.');
    }
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'];
    return MultiStopRoute(
      path: geometry is String ? PolylineCodec.decode(geometry) : const [],
      legs: [
        for (final leg in route['legs'] as List<dynamic>)
          TravelEstimate(
            meters: ((leg as Map<String, dynamic>)['distance'] as num)
                .toDouble(),
            duration: Duration(seconds: (leg['duration'] as num).round()),
          ),
      ],
    );
  }
}

/// A route through several stops.
class MultiStopRoute {
  const MultiStopRoute({required this.path, required this.legs});

  /// The road path through every stop, for drawing.
  final List<LatLng> path;

  /// Leg i goes from stop i to stop i + 1.
  final List<TravelEstimate> legs;
}

/// Itinerary legs this short are shown as walks.
const walkableLegMeters = 1500.0;

/// "12 min walk · 900 m" for short legs, else "20 min by road · 6.2 km".
String describeLeg(TravelEstimate leg) {
  String km(double m) => m < 1000
      ? '${(m / 10).round() * 10} m'
      : '${(m / 1000).toStringAsFixed(1)} km';
  String mins(Duration d) {
    final m = d.inMinutes < 1 ? 1 : d.inMinutes;
    return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  }

  if (leg.meters <= walkableLegMeters) {
    // About 4.5 km/h on foot.
    final walk = Duration(seconds: (leg.meters / 1.25).round());
    return '${mins(walk)} walk · ${km(leg.meters)}';
  }
  return '${mins(leg.duration)} by road · ${km(leg.meters)}';
}

/// The journey from where the user is to a place, by car and on foot, for
/// the place sheet. Uses a recent position so it shows quickly.
final journeyEstimateProvider = FutureProvider.autoDispose
    .family<JourneyEstimate, ({double lat, double lng})>((ref, place) async {
      final here = await ref
          .read(locationServiceProvider)
          .getCurrentLocation(acceptRecent: true);
      if (here == null) return const JourneyEstimate();
      final service = ref.read(directionsServiceProvider);
      final to = LatLng(place.lat, place.lng);
      Future<TravelEstimate?> attempt(TravelMode mode) async {
        try {
          return await service.estimate(from: here, to: to, mode: mode);
        } catch (_) {
          return null;
        }
      }

      final results = await Future.wait([
        attempt(TravelMode.car),
        attempt(TravelMode.foot),
      ]);
      return JourneyEstimate(byCar: results[0], onFoot: results[1]);
    });
