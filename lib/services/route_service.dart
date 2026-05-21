import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  RouteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 8);

  Future<List<LatLng>> computeRoutePolyline({
    required LatLng origin,
    required LatLng destination,
  }) async {
    return _fetchRouteGeometryWithProfile(
      waypoints: [origin, destination],
      profile: 'driving',
    );
  }

  Future<List<LatLng>> fetchRouteGeometry(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return const [];

    final walkingRoute = await _fetchRouteGeometryWithProfile(
      waypoints: waypoints,
      profile: 'foot',
    );
    if (walkingRoute.isNotEmpty) return walkingRoute;

    // The public OSRM server can reject some profiles/routes; driving keeps a
    // road-following visual fallback before the map falls back to straight lines.
    return _fetchRouteGeometryWithProfile(
      waypoints: waypoints,
      profile: 'driving',
    );
  }

  Future<List<LatLng>> _fetchRouteGeometryWithProfile({
    required List<LatLng> waypoints,
    required String profile,
  }) async {
    if (waypoints.length < 2) return const [];

    final coordinates = waypoints
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');

    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/$profile/$coordinates',
      {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': 'WakeMap/1.0 (OpenStreetMap flutter_map client)',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return const [];

      final firstRoute = routes.first;
      if (firstRoute is! Map<String, dynamic>) return const [];

      final geometry = firstRoute['geometry'];
      if (geometry is! Map<String, dynamic>) return const [];

      final routeCoordinates = geometry['coordinates'];
      if (routeCoordinates is! List) return const [];

      return _decodeRouteCoordinates(routeCoordinates);
    } catch (_) {
      return const [];
    }
  }

  List<LatLng> _decodeRouteCoordinates(List<dynamic> coordinates) {
    final points = <LatLng>[];

    for (final coordinate in coordinates) {
      if (coordinate is! List || coordinate.length < 2) continue;

      final lngValue = coordinate[0];
      final latValue = coordinate[1];
      if (lngValue is! num || latValue is! num) continue;

      points.add(LatLng(latValue.toDouble(), lngValue.toDouble()));
    }

    return List.unmodifiable(points);
  }
}
