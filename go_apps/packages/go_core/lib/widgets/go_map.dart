import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;

import '../config/app_config.dart';
import '../models/geo.dart';
import '../theme/go_theme.dart';

enum MarkerKind { pickup, dropoff, rider, store }

class GoMarker {
  const GoMarker(this.id, this.position, this.kind);
  final String id;
  final LatLng position;
  final MarkerKind kind;
}

gm.LatLng toGm(LatLng p) => gm.LatLng(p.lat, p.lng);
LatLng fromGm(gm.LatLng p) => LatLng(lat: p.latitude, lng: p.longitude);

/// Google Map when a key is configured; otherwise a lightweight schematic
/// that still shows the markers (useful in mock mode, tests, low-end phones).
class GoMap extends StatefulWidget {
  const GoMap({
    super.key,
    required this.center,
    this.markers = const [],
    this.zoom = 15,
    this.onCameraIdle,
    this.interactive = true,
    this.myLocation = false,
    this.followMarkerId,
    this.route = const [],
  });

  final LatLng center;
  final List<GoMarker> markers;
  final double zoom;
  final ValueChanged<LatLng>? onCameraIdle;
  final bool interactive;
  final bool myLocation;

  /// Keeps the camera on this marker as it moves (rider tracking).
  final String? followMarkerId;

  /// Road route to draw (decoded from the API's `route_polyline`).
  final List<LatLng> route;

  @override
  State<GoMap> createState() => GoMapState();
}

class GoMapState extends State<GoMap> {
  gm.GoogleMapController? _controller;
  LatLng? _cameraCenter;

  Future<void> moveTo(LatLng p) async {
    _cameraCenter = p;
    await _controller?.animateCamera(gm.CameraUpdate.newLatLng(toGm(p)));
    if (_controller == null) widget.onCameraIdle?.call(p);
  }

  @override
  void didUpdateWidget(covariant GoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final follow = widget.followMarkerId;
    if (follow != null) {
      final m = widget.markers.where((m) => m.id == follow).firstOrNull;
      if (m != null) _controller?.animateCamera(gm.CameraUpdate.newLatLng(toGm(m.position)));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double _hue(MarkerKind k) => switch (k) {
    MarkerKind.pickup => gm.BitmapDescriptor.hueGreen,
    MarkerKind.dropoff => gm.BitmapDescriptor.hueRed,
    MarkerKind.rider => gm.BitmapDescriptor.hueYellow,
    MarkerKind.store => gm.BitmapDescriptor.hueOrange,
  };

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.current.mapsEnabled) return _Schematic(center: widget.center, markers: widget.markers, route: widget.route);
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(target: toGm(widget.center), zoom: widget.zoom),
      onMapCreated: (c) => _controller = c,
      myLocationEnabled: widget.myLocation,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      liteModeEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onCameraMove: (p) => _cameraCenter = fromGm(p.target),
      onCameraIdle: () {
        final c = _cameraCenter;
        if (c != null) widget.onCameraIdle?.call(c);
      },
      polylines: {
        if (widget.route.length >= 2)
          gm.Polyline(
            polylineId: const gm.PolylineId('route'),
            points: [for (final p in widget.route) toGm(p)],
            color: GoColors.primary,
            width: 5,
          ),
      },
      markers: {
        for (final m in widget.markers)
          gm.Marker(markerId: gm.MarkerId(m.id), position: toGm(m.position), icon: gm.BitmapDescriptor.defaultMarkerWithHue(_hue(m.kind))),
      },
    );
  }
}

class _Schematic extends StatelessWidget {
  const _Schematic({required this.center, required this.markers, this.route = const []});
  final LatLng center;
  final List<GoMarker> markers;
  final List<LatLng> route;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) {
        // With 2+ markers, fit them all (with margin); otherwise ~2.5 km around center.
        var mid = center;
        var span = 0.025;
        final pts = [...markers.map((m) => m.position), ...route];
        if (pts.length >= 2) {
          final lats = pts.map((p) => p.lat), lngs = pts.map((p) => p.lng);
          final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
          final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
          mid = LatLng(lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2);
          final aspect = c.maxHeight / c.maxWidth;
          span = math.max(0.012, math.max(maxLng - minLng, (maxLat - minLat) / aspect) * 1.5);
        }
        Offset pos(LatLng p) =>
            Offset(c.maxWidth / 2 + (p.lng - mid.lng) / span * c.maxWidth, c.maxHeight / 2 - (p.lat - mid.lat) / span * c.maxWidth);
        return Container(
          color: dark ? const Color(0xFF17221E) : const Color(0xFFE3EEE8),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter(dark ? const Color(0xFF243530) : const Color(0xFFCADCD2)))),
              if (route.length >= 2) Positioned.fill(child: CustomPaint(painter: _RoutePainter([for (final p in route) pos(p)]))),
              for (final m in markers)
                Positioned(
                  left: pos(m.position).dx - 16,
                  top: pos(m.position).dy - 32,
                  child: Icon(
                    switch (m.kind) {
                      MarkerKind.rider => Icons.two_wheeler,
                      MarkerKind.store => Icons.storefront,
                      _ => Icons.location_on,
                    },
                    size: 32,
                    color: switch (m.kind) {
                      MarkerKind.pickup => GoColors.primary,
                      MarkerKind.dropoff => GoColors.danger,
                      MarkerKind.rider => GoColors.accent,
                      MarkerKind.store => GoColors.food,
                    },
                    shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.color != color;
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = GoColors.primary
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.points != points;
}

/// Google requires this notice wherever two-wheeler (motorcycle) routes are shown.
class RouteBetaNote extends StatelessWidget {
  const RouteBetaNote({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text('map.route_beta'.tr, style: TextStyle(fontSize: 11, color: GoColors.muted)),
  );
}
