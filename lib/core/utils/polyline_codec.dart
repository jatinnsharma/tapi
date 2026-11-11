import 'package:latlong2/latlong.dart';

class PolylineCodec {
  static String encode(List<LatLng> coords) {
    if (coords.isEmpty) return '';

    final result = StringBuffer();
    int lastLat = 0;
    int lastLng = 0;

    for (final coord in coords) {
      final lat = (coord.latitude * 1e5).round();
      final lng = (coord.longitude * 1e5).round();

      final dLat = lat - lastLat;
      final dLng = lng - lastLng;

      _encode(dLat, result);
      _encode(dLng, result);

      lastLat = lat;
      lastLng = lng;
    }

    return result.toString();
  }

  static void _encode(int value, StringBuffer result) {
    var v = value < 0 ? ~(value << 1) : value << 1;
    while (v >= 0x20) {
      result.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    result.writeCharCode(v + 63);
  }

  static List<LatLng> decode(String polyline) {
    final result = <LatLng>[];
    if (polyline.isEmpty) return result;

    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < polyline.length) {
      int b;
      int shift = 0;
      int r = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (r & 1) != 0 ? ~(r >> 1) : (r >> 1);
      lat += dLat;

      shift = 0;
      r = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (r & 1) != 0 ? ~(r >> 1) : (r >> 1);
      lng += dLng;

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }
}
