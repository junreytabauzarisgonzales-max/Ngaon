import '../models/geo.dart';

/// Decodes a Google encoded polyline (precision 5) into points.
/// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  try {
    while (index < encoded.length) {
      lat += next();
      lng += next();
      points.add(LatLng(lat: lat / 1e5, lng: lng / 1e5));
    }
  } catch (_) {
    // Malformed input: return what was decoded so far.
  }
  return points;
}
