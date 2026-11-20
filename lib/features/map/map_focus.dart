import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// A request, from another screen, to show a spot on the Map tab
/// ("Explore on Map" on a city). The Map consumes it: it moves there, shows
/// every place (fog off, since the spot may be far away), and clears it.
///
/// It is a request rather than a listened-to event because the Map tab may
/// not have been built yet when it is made.
final mapFocusProvider = NotifierProvider<MapFocusNotifier, MapFocus?>(
  MapFocusNotifier.new,
);

class MapFocus {
  const MapFocus(this.center, {this.zoom = 13});

  final LatLng center;
  final double zoom;
}

class MapFocusNotifier extends Notifier<MapFocus?> {
  @override
  MapFocus? build() => null;

  void focus(MapFocus focus) => state = focus;

  void clear() => state = null;
}
